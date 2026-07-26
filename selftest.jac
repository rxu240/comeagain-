"""End-to-end backend check: synthesise a take, run the API walker, print it.

`jac run selftest.jac` exercises exactly what the browser hits - decode,
segment, score eight dimensions per segment, persist the graph, coach - with
no server and no microphone.
"""

import from engine.fixture { synth_take }
import from engine.scoring { fmt_time, fmt1 }
import from api { AnalyseTake, ListTakes, LoadTake, DeleteTake }


with entry:__main__ {
    audio = synth_take();
    print("payload      ", len(audio), "base64 chars");

    res = root spawn AnalyseTake(audio=audio, label="Self test", purpose="Investor pitch rehearsal");
    rep = res.reports[0];

    print("");
    print("take         ", rep.label, "|", fmt1(rep.duration) + "s", "| overall", fmt1(rep.overall));
    print("coached by   ", rep.coachedBy);
    print("summary      ", rep.summary);
    print("ribbon points", len(rep.contour), "contour /", len(rep.envelope), "envelope");
    print("");

    print("--- whole take ---");
    for d in rep.dimensions {
        bits: list[str] = [];
        for m in d.metrics { bits.append(m.label + " " + m.value); }
        print("  " + d.name.ljust(13) + fmt1(d.score).rjust(5) + "  " + d.band.ljust(7) + d.headline);
        print("               " + ", ".join(bits));
    }

    print("");
    print("--- segments (" + str(len(rep.segments)) + ") ---");
    for s in rep.segments {
        print("  #" + str(s.idx) + "  " + fmt_time(s.start) + "-" + fmt_time(s.end)
              + "  score " + fmt1(s.score) + "  " + s.headline);
        for d in s.dimensions {
            if d.score < 60.0 {
                print("        weak: " + d.name + " " + fmt1(d.score) + " - " + d.headline);
            }
        }
    }

    print("");
    print("--- moments (" + str(len(rep.moments)) + ") ---");
    for m in rep.moments {
        print("  " + fmt_time(m.t) + "  [" + m.dimension + "/" + m.severity + "] " + m.note);
    }

    print("");
    print("--- coaching ---");
    for c in rep.coaching { print("  - " + c); }

    print("");
    listed = root spawn ListTakes();
    print("stored takes ", len(listed.reports[0]));

    loaded = root spawn LoadTake(takeId=rep.takeId);
    print("reloaded     ", loaded.reports[0].label,
          "| segments", len(loaded.reports[0].segments),
          "| dims", len(loaded.reports[0].dimensions));

    gone = root spawn DeleteTake(takeId=rep.takeId);
    print("deleted      ", gone.reports[0]);
}
