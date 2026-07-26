"""Microphone capture and decoding, client side.

The browser does all codec work. Whatever comes in - a MediaRecorder blob, an
uploaded mp3, m4a, wav or ogg - is decoded by the Web Audio API, downmixed and
resampled to 16 kHz mono, then sent to the server as base64 int16 PCM. The
server therefore never needs ffmpeg and never has to know a container format.
"""

glob _stream: any = None;
glob _recorder: any = None;
glob _chunks: list[any] = [];
glob _meterCtx: any = None;
glob _analyser: any = None;
glob _meterBuf: any = None;

glob TARGET_RATE: int = 16000;
glob MAX_SECONDS: float = 180.0;


"""Decoded audio, ready to send and to play back.

`error` carries a message meant for the user. Decoding fails for ordinary
reasons - a recording that captured nothing, a file the browser has no codec
for - and those deserve an instruction, not a raw EncodingError.
"""
obj Decoded {
    has b64: str = "",
        duration: float = 0.0,
        url: str = "",
        error: str = "";
}


"""Best recording container this browser will give us."""
def pickMimeType() -> str {
    options = [
        "audio/webm;codecs=opus",
        "audio/webm",
        "audio/mp4",
        "audio/ogg;codecs=opus"
    ];
    for mt in options {
        if MediaRecorder.isTypeSupported(mt) { return mt; }
    }
    return "";
}


"""True when this browser exposes a microphone at all."""
def:pub captureSupported() -> bool {
    return Boolean(navigator.mediaDevices) and Boolean(window.MediaRecorder);
}


"""Release the microphone so the browser drops its recording indicator."""
def:pub releaseMic() -> None {
    if _stream {
        tracks = _stream.getTracks();
        for t in tracks { t.stop(); }
    }
    if _meterCtx {
        try { _meterCtx.close(); } except Exception { console.debug("meter already closed"); }
    }
    _stream = None;
    _recorder = None;
    _meterCtx = None;
    _analyser = None;
    _meterBuf = None;
}


"""Current input loudness, 0-1, for the live meter on the record button."""
def:pub liveLevel() -> float {
    if not _analyser { return 0.0; }
    _analyser.getFloatTimeDomainData(_meterBuf);
    total = 0.0;
    i = 0;
    n = _meterBuf.length;
    while i < n {
        v = _meterBuf[i];
        total = total + v * v;
        i = i + 1;
    }
    rms = Math.sqrt(total / n);
    return Math.min(1.0, rms * 7.0);
}


"""Open the microphone and start recording. False if permission is refused."""
async def:pub beginCapture() -> bool {
    try {
        constraints = {
            "audio": {
                "echoCancellation": False,
                "noiseSuppression": False,
                "autoGainControl": False
            }
        };
        _stream = await navigator.mediaDevices.getUserMedia(constraints);
        _chunks = [];

        _meterCtx = new(AudioContext);
        _analyser = _meterCtx.createAnalyser();
        _analyser.fftSize = 1024;
        _meterCtx.createMediaStreamSource(_stream).connect(_analyser);
        _meterBuf = new(Float32Array, _analyser.fftSize);

        mt = pickMimeType();
        _recorder = new(MediaRecorder, _stream, {"mimeType": mt}) if mt != "" else new(MediaRecorder, _stream);
        _recorder.ondataavailable = lambda(e: any) {
            if e.data and e.data.size > 0 { _chunks.push(e.data); }
        };
        # No timeslice: one well-formed blob on stop. Chunked output has to be
        # reassembled, and a concatenation of fragments is not always decodable.
        _recorder.start();
        return True;
    } except Exception as err {
        console.error("[tonecraft] mic unavailable:", err);
        releaseMic();
        return False;
    }
}


"""Stop recording and resolve with the captured Blob."""
def:pub endCapture() -> any {
    return new(Promise, lambda(resolve: any, reject: any) {
        rec = _recorder;
        if not rec {
            reject.call(None, "not recording");
        } else {
            rec.onstop = lambda(e: any) {
                blob = new(Blob, _chunks, {"type": rec.mimeType or "audio/webm"});
                releaseMic();
                resolve.call(None, blob);
            };
            rec.stop();
        }
    });
}


"""Read an ArrayBuffer out as base64, via the browser's own encoder."""
def toBase64(buffer: any) -> any {
    return new(Promise, lambda(resolve: any, reject: any) {
        reader = new(FileReader);
        reader.onload = lambda(e: any) {
            text = String(reader.result);
            resolve.call(None, text.slice(text.indexOf(",") + 1));
        };
        reader.onerror = lambda(e: any) { reject.call(None, "could not read audio"); };
        reader.readAsDataURL(new(Blob, [buffer]));
    });
}


"""Decode any audio source to 16 kHz mono int16 PCM, base64 encoded."""
async def:pub decodeToPcm(source: any) -> Decoded {
    # A recorder that captured nothing yields an empty blob, and decodeAudioData
    # reports that as EncodingError - the same thing it says about a corrupt
    # file. Separate the two here so the user gets the right instruction.
    size = Number(source.size or 0);
    if size < 2048 {
        return Decoded(
            error="That recording came out empty. Hold the button for a few seconds before stopping, and check the right microphone is selected in your browser."
        );
    }

    raw = await source.arrayBuffer();
    ctx = new(AudioContext);
    audio = None;
    try {
        audio = await ctx.decodeAudioData(raw.slice(0));
    } except Exception {
        try { ctx.close(); } except Exception { console.debug("audio context already closed"); }
        return Decoded(
            error="We could not decode that audio. WAV, MP3, M4A, OGG and WebM all work - if this was a recording, try again."
        );
    }
    ctx.close();

    if not audio or audio.duration <= 0.0 {
        return Decoded(error="That file decoded to no audio at all. Try a different recording.");
    }

    seconds = audio.duration;
    if seconds > MAX_SECONDS { seconds = MAX_SECONDS; }

    frames = Math.max(Math.ceil(seconds * TARGET_RATE), 1);
    off = new(OfflineAudioContext, 1, frames, TARGET_RATE);
    srcNode = off.createBufferSource();
    srcNode.buffer = audio;
    srcNode.connect(off.destination);
    srcNode.start(0);

    rendered = await off.startRendering();
    data = rendered.getChannelData(0);

    n = data.length;
    ints = new(Int16Array, n);
    i = 0;
    while i < n {
        v = data[i];
        if v > 1.0 { v = 1.0; }
        if v < -1.0 { v = -1.0; }
        ints[i] = v * 32767.0;
        i = i + 1;
    }

    encoded = await toBase64(ints.buffer);
    return Decoded(
        b64=encoded,
        duration=seconds,
        url=URL.createObjectURL(source)
    );
}


"""Reject files we cannot decode before the user waits on an upload."""
def:pub looksLikeAudio(file: any) -> bool {
    kind = String(file.type or "");
    if kind.startsWith("audio/") or kind.startsWith("video/") { return True; }
    name = String(file.name or "").toLowerCase();
    for ext in [".mp3", ".wav", ".m4a", ".aac", ".ogg", ".oga", ".webm", ".flac"] {
        if name.endsWith(ext) { return True; }
    }
    return False;
}
