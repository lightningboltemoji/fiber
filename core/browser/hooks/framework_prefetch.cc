#include "fiber/browser/hooks/framework_prefetch.h"

#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <pthread.h>
#include <sys/qos.h>
#include <unistd.h>

#include <algorithm>
#include <string>
#include <string_view>

#include "base/compiler_specific.h"

namespace fiber {

namespace {

// How much each read-ahead asks for.
constexpr off_t kChunkSize = 16 << 20;

struct Prefetch {
  std::string path;
  // Everything before __LINKEDIT: the code and data that startup runs from.
  off_t length = 0;
};

// A segment's name, which fills its 16 bytes or ends at a NUL.
std::string_view SegmentName(const segment_command_64& segment) {
  std::string_view name(segment.segname, sizeof(segment.segname));
  return name.substr(0, name.find('\0'));
}

// The image this code is in, and how much of its file to read.
bool FindFramework(Prefetch& prefetch) {
  const auto self = reinterpret_cast<uintptr_t>(&PrefetchFramework);
  for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
    const auto* header =
        reinterpret_cast<const mach_header_64*>(_dyld_get_image_header(i));
    if (!header || header->magic != MH_MAGIC_64) {
      continue;
    }
    const intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    bool contains_self = false;
    off_t linkedit_offset = 0;
    const auto* command =
        reinterpret_cast<const load_command*>(UNSAFE_BUFFERS(header + 1));
    for (uint32_t j = 0; j < header->ncmds; ++j) {
      if (command->cmd == LC_SEGMENT_64) {
        const auto* segment =
            reinterpret_cast<const segment_command_64*>(command);
        const std::string_view name = SegmentName(*segment);
        const uintptr_t start = segment->vmaddr + slide;
        if (name == SEG_TEXT && self >= start &&
            self < start + segment->vmsize) {
          contains_self = true;
        }
        if (name == SEG_LINKEDIT) {
          linkedit_offset = static_cast<off_t>(segment->fileoff);
        }
      }
      command = reinterpret_cast<const load_command*>(
          UNSAFE_BUFFERS(reinterpret_cast<const char*>(command) +
                         command->cmdsize));
    }
    if (contains_self) {
      prefetch.path = _dyld_get_image_name(i);
      prefetch.length = linkedit_offset;
      return linkedit_offset > 0;
    }
  }
  return false;
}

void* ReadAhead(void* context) {
  Prefetch* prefetch = static_cast<Prefetch*>(context);
  int fd = open(prefetch->path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd >= 0) {
    // Waits for each chunk: what's already in memory returns at once.
    for (off_t offset = 0; offset < prefetch->length; offset += kChunkSize) {
      radvisory advice = {
          .ra_offset = offset,
          .ra_count = static_cast<int>(
              std::min(kChunkSize, prefetch->length - offset)),
      };
      if (fcntl(fd, F_RDADVISE, &advice) == -1) {
        break;
      }
    }
    close(fd);
  }
  delete prefetch;
  return nullptr;
}

}  // namespace

void PrefetchFramework(int argc, const char** argv) {
  // Other processes start once the browser has (mostly) read it.
  for (int i = 1; i < argc; ++i) {
    if (std::string_view(UNSAFE_BUFFERS(argv[i])).starts_with("--type=")) {
      return;
    }
  }
  auto* prefetch = new Prefetch;
  if (!FindFramework(*prefetch)) {
    delete prefetch;
    return;
  }
  // At utility QoS, whose reads give way to the main thread's: those are for
  // what startup needs now, and waiting behind the read-ahead slows the
  // window by 20 ms.
  pthread_attr_t attributes;
  pthread_attr_init(&attributes);
  pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
  pthread_attr_set_qos_class_np(&attributes, QOS_CLASS_UTILITY, 0);
  pthread_t thread;
  if (pthread_create(&thread, &attributes, &ReadAhead, prefetch) != 0) {
    delete prefetch;
  }
  pthread_attr_destroy(&attributes);
}

}  // namespace fiber
