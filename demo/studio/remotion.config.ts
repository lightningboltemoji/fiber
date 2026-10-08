import {Config} from '@remotion/cli/config';

// Takes are recorded into demo/takes/<tape>/ by the director.
Config.setPublicDir('../takes');
Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(95);
Config.setCodec('h264');
Config.setCrf(18);
