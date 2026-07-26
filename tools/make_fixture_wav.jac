"""Write the synthetic take to a real WAV file, for testing the upload path.

`jac run tools/make_fixture_wav.jac` produces `fixture-take.wav` in the project
root - a decodable file the browser can ingest exactly like a user's upload.
"""

import base64;
import wave;
import from engine.fixture { synth_take }
import from engine.dsp { SR }


with entry:__main__ {
    pcm = base64.b64decode(synth_take());
    handle = wave.open("fixture-take.wav", "wb");
    handle.setnchannels(1);
    handle.setsampwidth(2);
    handle.setframerate(SR);
    handle.writeframes(pcm);
    handle.close();
    print("wrote fixture-take.wav", len(pcm), "bytes of PCM");
}
