#include "fiber/browser/profiles/chrome_import.h"

#import <AppKit/AppKit.h>

#include <array>
#include <string_view>
#include <utility>

#include "base/apple/foundation_util.h"
#include "base/containers/span.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/bind_post_task.h"
#include "base/task/thread_pool.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_attributes_init_params.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_avatar_icon_util.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_window.h"
#include "chrome/common/chrome_constants.h"
#include "components/os_crypt/async/browser/os_crypt_async.h"
#include "components/os_crypt/async/common/encryptor.h"
#include "crypto/aes_cbc.h"
#include "crypto/apple/keychain_v2.h"
#include "sql/database.h"
#include "sql/statement.h"
#include "sql/transaction.h"
#include "third_party/boringssl/src/include/openssl/evp.h"

namespace fiber {

namespace {

using ProgressCallback =
    base::RepeatingCallback<void(const std::u16string& step)>;
using DoneCallback =
    base::OnceCallback<void(std::optional<std::u16string> error)>;

// Chrome's names for its files, which a Fiber profile's share.
constexpr char kBookmarks[] = "Bookmarks";
constexpr char kAccountBookmarks[] = "AccountBookmarks";
constexpr char kLoginData[] = "Login Data";
constexpr char kAccountLoginData[] = "Login Data For Account";
constexpr char kCookies[] = "Cookies";
constexpr const char* kHistoryDatabases[] = {"History", "Favicons",
                                             "Top Sites", "Shortcuts"};
// Beside a SQLite database, its journal or write-ahead log.
constexpr const char* kDatabaseSideFiles[] = {"-journal", "-wal", "-shm"};

base::FilePath ChromeUserDataDir() {
  return base::apple::GetUserLibraryPath()
      .Append("Application Support")
      .Append("Google")
      .Append("Chrome");
}

bool IsChromeRunning() {
  return [NSRunningApplication
             runningApplicationsWithBundleIdentifier:@"com.google.Chrome"]
             .count > 0;
}

std::optional<base::DictValue> ReadJSONDict(const base::FilePath& path) {
  std::string json;
  if (!base::ReadFileToString(path, &json)) {
    return std::nullopt;
  }
  std::optional<base::Value> value = base::JSONReader::Read(
      json, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
  if (!value || !value->is_dict()) {
    return std::nullopt;
  }
  return std::move(*value).TakeDict();
}

// Chrome's key to its passwords and cookies, derived from the keychain's as
// os_crypt does (keychain_key_provider.mm). The keychain asks the user first.
std::optional<std::vector<uint8_t>> ChromeKey() {
  base::expected<std::vector<uint8_t>, OSStatus> password =
      crypto::apple::KeychainV2::GetInstance().FindGenericPassword(
          "Chrome Safe Storage", "Chrome");
  if (!password.has_value() || password->empty()) {
    return std::nullopt;
  }
  constexpr std::string_view kSalt = "saltysalt";
  constexpr unsigned kIterations = 1003;
  std::vector<uint8_t> key(16);
  if (!PKCS5_PBKDF2_HMAC_SHA1(
          reinterpret_cast<const char*>(password->data()), password->size(),
          reinterpret_cast<const uint8_t*>(kSalt.data()), kSalt.size(),
          kIterations, key.size(), key.data())) {
    return std::nullopt;
  }
  return key;
}

// A value Chrome encrypted with `key`: "v10", then AES-128-CBC.
std::optional<std::string> DecryptChromeValue(base::span<const uint8_t> key,
                                              base::span<const uint8_t> value) {
  constexpr std::string_view kPrefix = "v10";
  if (!base::as_string_view(value).starts_with(kPrefix)) {
    return std::nullopt;
  }
  std::array<uint8_t, crypto::aes_cbc::kBlockSize> iv;
  iv.fill(' ');
  std::optional<std::vector<uint8_t>> plaintext =
      crypto::aes_cbc::Decrypt(key, iv, value.subspan(kPrefix.size()));
  if (!plaintext) {
    return std::nullopt;
  }
  return std::string(base::as_string_view(*plaintext));
}

// Encrypts `table`'s `column` with Fiber's key in place of Chrome's, deleting
// the rows it can't decrypt: Fiber would, but only after failing on them.
bool ReencryptColumn(sql::Database& db,
                     std::string_view table,
                     std::string_view column,
                     base::span<const uint8_t> key,
                     const os_crypt_async::Encryptor& encryptor) {
  if (!db.DoesTableExist(table)) {
    return true;
  }
  std::vector<std::pair<int64_t, std::optional<std::vector<uint8_t>>>> rows;
  sql::Statement select(db.GetUniqueStatement(
      base::StrCat({"SELECT rowid, ", column, " FROM ", table})));
  while (select.Step()) {
    base::span<const uint8_t> value = select.ColumnBlob(1);
    if (value.empty()) {
      continue;
    }
    std::optional<std::string> plaintext = DecryptChromeValue(key, value);
    rows.emplace_back(select.ColumnInt64(0),
                      plaintext ? encryptor.EncryptString(*plaintext)
                                : std::nullopt);
  }
  if (!select.Succeeded()) {
    return false;
  }
  sql::Statement update(db.GetUniqueStatement(base::StrCat(
      {"UPDATE ", table, " SET ", column, " = ? WHERE rowid = ?"})));
  sql::Statement remove(db.GetUniqueStatement(
      base::StrCat({"DELETE FROM ", table, " WHERE rowid = ?"})));
  for (const auto& [rowid, ciphertext] : rows) {
    sql::Statement& statement = ciphertext ? update : remove;
    statement.Reset(/*clear_bound_vars=*/true);
    if (ciphertext) {
      update.BindBlob(0, *ciphertext);
      update.BindInt64(1, rowid);
    } else {
      remove.BindInt64(0, rowid);
    }
    if (!statement.Run()) {
      return false;
    }
  }
  return true;
}

bool CopyDatabase(const base::FilePath& from, const base::FilePath& to) {
  if (!base::PathExists(from) || !base::CopyFile(from, to)) {
    return false;
  }
  for (const char* suffix : kDatabaseSideFiles) {
    base::FilePath side(from.value() + suffix);
    if (base::PathExists(side)) {
      base::CopyFile(side, base::FilePath(to.value() + suffix));
    }
  }
  return true;
}

void DeleteDatabase(const base::FilePath& path) {
  base::DeleteFile(path);
  for (const char* suffix : kDatabaseSideFiles) {
    base::DeleteFile(base::FilePath(path.value() + suffix));
  }
}

// Chrome keeps a Google account's bookmarks apart from the profile's. Fiber
// signs in to no account, so they join the profile's.
void CopyBookmarks(const base::FilePath& source, const base::FilePath& target) {
  std::optional<base::DictValue> bookmarks =
      ReadJSONDict(source.Append(kBookmarks));
  std::optional<base::DictValue> account =
      ReadJSONDict(source.Append(kAccountBookmarks));
  if (!bookmarks) {
    bookmarks = std::move(account);
    account.reset();
  }
  if (!bookmarks) {
    return;
  }
  base::DictValue* roots = bookmarks->FindDict("roots");
  const base::DictValue* account_roots =
      account ? account->FindDict("roots") : nullptr;
  if (roots && account_roots) {
    for (const char* root : {"bookmark_bar", "other", "synced"}) {
      base::DictValue* folder = roots->FindDict(root);
      const base::DictValue* account_folder = account_roots->FindDict(root);
      base::ListValue* children =
          folder ? folder->FindList("children") : nullptr;
      const base::ListValue* account_children =
          account_folder ? account_folder->FindList("children") : nullptr;
      if (!children || !account_children) {
        continue;
      }
      // Clashing IDs and UUIDs are reassigned as the model loads.
      for (const base::Value& child : *account_children) {
        children->Append(child.Clone());
      }
    }
  }
  // Sync's state, for an account Fiber isn't signed in to, and a checksum the
  // merge breaks.
  bookmarks->Remove("checksum");
  bookmarks->Remove("sync_metadata");
  if (std::optional<std::string> json = base::WriteJsonWithOptions(
          *bookmarks, base::JSONWriter::OPTIONS_PRETTY_PRINT)) {
    base::WriteFile(target.Append(kBookmarks), *json);
  }
}

// Adds the Google account's passwords, which Chrome keeps apart, to the
// profile's, as with bookmarks. Those the profile has already stay.
bool MergeAccountLogins(sql::Database& db, const base::FilePath& account) {
  if (!db.AttachDatabase(account, "account")) {
    return false;
  }
  std::vector<std::string> columns;
  sql::Statement info(db.GetUniqueStatement("PRAGMA table_info(logins)"));
  while (info.Step()) {
    if (std::string name = info.ColumnString(1); name != "id") {
      columns.push_back(std::move(name));
    }
  }
  const std::string list = base::JoinString(columns, ", ");
  bool merged = !columns.empty() &&
                db.Execute(base::StrCat({"INSERT OR IGNORE INTO main.logins (",
                                         list, ") SELECT ", list,
                                         " FROM account.logins"}));
  return db.DetachDatabase("account") && merged;
}

bool CopyPasswords(const base::FilePath& source,
                   const base::FilePath& target,
                   base::span<const uint8_t> key,
                   const os_crypt_async::Encryptor& encryptor) {
  const base::FilePath login_data = target.Append(kLoginData);
  const base::FilePath account = target.Append(kAccountLoginData);
  const bool has_profile_logins =
      CopyDatabase(source.Append(kLoginData), login_data);
  const bool has_account_logins = CopyDatabase(
      source.Append(kAccountLoginData),
      has_profile_logins ? account : login_data);
  if (!has_profile_logins && !has_account_logins) {
    return true;
  }
  bool copied = false;
  {
    sql::Database db(sql::Database::Tag("Passwords"));
    if (db.Open(login_data) &&
        (!has_profile_logins || !has_account_logins ||
         MergeAccountLogins(db, account))) {
      sql::Transaction transaction(&db);
      copied = transaction.Begin() &&
               ReencryptColumn(db, "logins", "password_value", key,
                               encryptor) &&
               ReencryptColumn(db, "password_notes", "value", key,
                               encryptor) &&
               // Sync's, for an account Fiber isn't signed in to.
               (!db.DoesTableExist("sync_entities_metadata") ||
                db.Execute("DELETE FROM sync_entities_metadata")) &&
               (!db.DoesTableExist("sync_model_metadata") ||
                db.Execute("DELETE FROM sync_model_metadata")) &&
               transaction.Commit();
    }
  }
  if (has_profile_logins && has_account_logins) {
    DeleteDatabase(account);
  }
  if (!copied) {
    DeleteDatabase(login_data);
  }
  return copied;
}

bool CopyCookies(const base::FilePath& source,
                 const base::FilePath& target,
                 base::span<const uint8_t> key,
                 const os_crypt_async::Encryptor& encryptor) {
  const base::FilePath cookies = target.Append(kCookies);
  if (!CopyDatabase(source.Append(kCookies), cookies)) {
    return true;
  }
  bool copied = false;
  {
    sql::Database db(sql::Database::Tag("Cookie"));
    if (db.Open(cookies)) {
      sql::Transaction transaction(&db);
      copied = transaction.Begin() &&
               ReencryptColumn(db, "cookies", "encrypted_value", key,
                               encryptor) &&
               transaction.Commit();
    }
  }
  if (!copied) {
    DeleteDatabase(cookies);
  }
  return copied;
}

// Fills `target`, a new profile's directory, from Chrome's profile at
// `source`. Waits for the user to answer the keychain.
bool CopyProfile(const base::FilePath& source,
                 const base::FilePath& target,
                 scoped_refptr<os_crypt_async::Encryptor> encryptor,
                 ProgressCallback progress) {
  const std::optional<std::vector<uint8_t>> key = ChromeKey();
  if (!base::DeletePathRecursively(target) || !base::CreateDirectory(target)) {
    return false;
  }
  progress.Run(u"Copying bookmarks and history…");
  CopyBookmarks(source, target);
  for (const char* name : kHistoryDatabases) {
    CopyDatabase(source.Append(name), target.Append(name));
  }
  if (key) {
    progress.Run(u"Copying passwords…");
    CopyPasswords(source, target, *key, *encryptor);
    progress.Run(u"Copying cookies…");
    CopyCookies(source, target, *key, *encryptor);
  }
  return true;
}

void OnImportedProfileInitialized(size_t avatar_index,
                                  DoneCallback done,
                                  Profile* profile) {
  if (!profile) {
    std::move(done).Run(u"Fiber couldn’t open the new profile.");
    return;
  }
  profiles::SetDefaultProfileAvatarIndex(profile, avatar_index);
  profiles::OpenBrowserWindowForProfile(base::DoNothing(),
                                        /*always_create=*/false,
                                        /*is_new_profile=*/false,
                                        /*open_command_line_urls=*/false,
                                        profile);
  std::move(done).Run(std::nullopt);
}

void OpenImportedProfile(const ChromeProfile& source,
                         const base::FilePath& target,
                         DoneCallback done,
                         bool copied) {
  if (!copied) {
    std::move(done).Run(u"Fiber couldn’t make the new profile.");
    return;
  }
  ProfileManager* manager = g_browser_process->profile_manager();
  ProfileAttributesStorage& storage = manager->GetProfileAttributesStorage();
  const size_t avatar_index =
      profiles::IsModernAvatarIconIndex(source.avatar_index)
          ? source.avatar_index
          : storage.ChooseAvatarIconIndexForNewProfile();
  ProfileAttributesInitParams params;
  params.profile_path = target;
  params.profile_name = source.name.empty() ? u"Chrome" : source.name;
  params.icon_index = avatar_index;
  storage.AddProfile(std::move(params));
  manager->CreateProfileAsync(
      target, base::BindOnce(&OnImportedProfileInitialized, avatar_index,
                             std::move(done)));
}

// As ProfileManager::CreateMultiProfileAsync() picks one, without clearing it
// out: the import fills it before the profile first loads.
base::FilePath NextProfilePath() {
  ProfileManager* manager = g_browser_process->profile_manager();
  ProfileAttributesStorage& storage = manager->GetProfileAttributesStorage();
  base::FilePath path;
  do {
    path = manager->GenerateNextProfileDirectoryPath();
  } while (storage.GetProfileAttributesWithPath(path));
  return path;
}

void CopyWithEncryptor(const ChromeProfile& source,
                       ProgressCallback progress,
                       DoneCallback done,
                       scoped_refptr<os_crypt_async::Encryptor> encryptor) {
  const base::FilePath target = NextProfilePath();
  // Quitting shouldn't wait for the keychain, and what's left is a directory
  // no profile uses.
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::CONTINUE_ON_SHUTDOWN},
      base::BindOnce(&CopyProfile, source.path, target, std::move(encryptor),
                     base::BindPostTaskToCurrentDefault(progress)),
      base::BindOnce(&OpenImportedProfile, source, target, std::move(done)));
}

}  // namespace

ChromeProfile::ChromeProfile() = default;
ChromeProfile::ChromeProfile(const ChromeProfile&) = default;
ChromeProfile& ChromeProfile::operator=(const ChromeProfile&) = default;
ChromeProfile::~ChromeProfile() = default;

std::vector<ChromeProfile> FindChromeProfiles() {
  const base::FilePath user_data_dir = ChromeUserDataDir();
  std::optional<base::DictValue> local_state =
      ReadJSONDict(user_data_dir.Append(chrome::kLocalStateFilename));
  const base::DictValue* info_cache =
      local_state ? local_state->FindDictByDottedPath("profile.info_cache")
                  : nullptr;
  if (!info_cache) {
    return {};
  }
  std::vector<ChromeProfile> found;
  for (const auto [directory, value] : *info_cache) {
    const base::DictValue* info = value.GetIfDict();
    ChromeProfile profile;
    profile.path = user_data_dir.Append(directory);
    if (!info || info->FindBool("is_ephemeral").value_or(false) ||
        !base::DirectoryExists(profile.path)) {
      continue;
    }
    if (const std::string* name = info->FindString("name")) {
      profile.name = base::UTF8ToUTF16(*name);
    }
    if (const std::string* user_name = info->FindString("user_name")) {
      profile.user_name = base::UTF8ToUTF16(*user_name);
    }
    const std::string* avatar = info->FindString("avatar_icon");
    if (!avatar ||
        !profiles::IsDefaultAvatarIconUrl(*avatar, &profile.avatar_index)) {
      profile.avatar_index = profiles::GetPlaceholderAvatarIndex();
    }
    if (const std::string* picture =
            info->FindString("gaia_picture_file_name")) {
      profile.picture = base::ReadFileToBytes(profile.path.Append(*picture))
                            .value_or(std::vector<uint8_t>());
    }
    found.push_back(std::move(profile));
  }
  std::ranges::sort(found, {}, [](const ChromeProfile& profile) {
    return base::ToLowerASCII(profile.name);
  });
  return found;
}

void ImportChromeProfile(const ChromeProfile& source,
                         ProgressCallback progress,
                         DoneCallback done) {
  if (IsChromeRunning()) {
    std::move(done).Run(u"Quit Chrome, then try again.");
    return;
  }
  progress.Run(u"Waiting for access to Chrome’s passwords…");
  g_browser_process->os_crypt_async()->GetInstance(base::BindOnce(
      &CopyWithEncryptor, source, std::move(progress), std::move(done)));
}

}  // namespace fiber
