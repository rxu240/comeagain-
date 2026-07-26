"""Handlers for AppShell, kept out of the render body."""


impl AppShell.startRec() -> None {
    error = "";
    status = "";
    opened = await beginCapture();
    if not opened {
        error = "We could not open the microphone. Check this site's permission and try again.";
        return;
    }
    _startedAt = Date.now();
    recording = True;
    elapsed = 0.0;
    _ticker = setInterval(lambda {
        elapsed = (Date.now() - _startedAt) / 1000.0;
        level = liveLevel();
    }, 70);
}


impl AppShell.stopRec() -> None {
    haltTicker();
    recording = False;
    level = 0.0;
    try {
        captured = await endCapture();
        await analyse(captured);
    } except Exception as err {
        releaseMic();
        busy = False;
        status = "";
        error = "That recording did not save. " + String(err);
    }
}


impl AppShell.handleFile(file: any) -> None {
    if not looksLikeAudio(file) {
        error = "That file is not audio we can read. Try mp3, m4a, wav, ogg or webm.";
        return;
    }
    error = "";
    analyse(file);
}


impl AppShell.analyse(source: any) -> None {
    busy = True;
    error = "";
    status = "Decoding audio";

    try {
        decoded = await decodeToPcm(source);
        if decoded.error != "" {
            busy = False;
            status = "";
            error = decoded.error;
            return;
        }
        if decoded.duration < 1.5 {
            busy = False;
            status = "";
            error = "That clip is only " + String(Math.round(decoded.duration * 10.0) / 10.0) + "s. Ten seconds or more gives a real result.";
            return;
        }

        status = "Measuring delivery";
        result = root spawn AnalyseTake(audio=decoded.b64, label="", purpose=purpose);

        if result.reports and len(result.reports) > 0 {
            audioUrl = decoded.url;
            take = result.reports[0];
            status = "";
            busy = False;
        } else {
            busy = False;
            status = "";
            error = "The analyser came back empty. Try a slightly longer clip.";
        }
    } except Exception as err {
        busy = False;
        status = "";
        # Decode problems are handled above, so anything here is the round trip
        # to the analyser rather than the audio itself.
        error = "The analyser did not respond. Check the server is still running, then try again. (" + String(err) + ")";
    }
}


impl AppShell.reset() -> None {
    haltTicker();
    releaseMic();
    if audioUrl != "" { URL.revokeObjectURL(audioUrl); }
    take = None;
    audioUrl = "";
    elapsed = 0.0;
    level = 0.0;
    status = "";
    error = "";
    busy = False;
    recording = False;
}
