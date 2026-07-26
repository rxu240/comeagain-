"""Bottom sheet with one utterance's full readout.

This is where the promise of segment-level feedback is actually paid off: the
eight dimensions scored for this stretch alone, the moments flagged inside it,
and a control that plays back only these seconds.
"""

sv import from ..engine.model { SegmentReport }
import from ".ui.drawer" { Drawer, DrawerContent, DrawerHeader, DrawerTitle, DrawerDescription }
import from ".ui.button" { Button }
import from .DimensionCard { DimensionCard }
import from .ScoreCrest { bandText, bandLabel }
import from .MomentList { MomentList }
import from "..lib.format" { fmtRange }


def:pub SegmentSheet(
    segment: SegmentReport | None,
    open: bool,
    onOpenChange: Callable[[bool], None],
    onPlay: Callable[[float, float], None]
) -> JsxElement {
    return <Drawer open={open} onOpenChange={onOpenChange}>
        <DrawerContent className="bg-transparent border-0">
            <div className="glass rounded-t-3xl max-h-[86svh] overflow-y-auto safe-bottom">
                {if segment == None {
                    <DrawerHeader>
                        <DrawerTitle className="display">Nothing selected</DrawerTitle>
                    </DrawerHeader>
                    skip;
                }}

                {if segment != None {
                    <DrawerHeader className="px-6 pt-6 pb-3 items-start text-left sm:text-left">
                        <span className="eyebrow block text-left">
                            {"Utterance " + String(segment.idx + 1) + " · " + fmtRange(segment.start, segment.end)}
                        </span>
                        <DrawerTitle className="display text-2xl mt-2 text-ink-900 text-left">
                            {segment.headline}
                        </DrawerTitle>
                        <DrawerDescription className={"mono text-xs mt-1 text-left " + bandText(segment.dimensions[0].band)}>
                            {String(Math.round(segment.score)) + " / 100 · " + bandLabel(segment.dimensions[0].band)}
                        </DrawerDescription>
                    </DrawerHeader>

                    <div className="px-6 pb-2">
                        <Button
                            variant="ghost"
                            onClick={lambda e: MouseEvent { onPlay(segment.start, segment.end); }}
                            className="glass-btn rounded-full h-11 px-6 mono text-[11px] tracking-[0.2em] uppercase text-ink-600"
                        >
                            {"Play this line"}
                        </Button>
                    </div>

                    <div className="px-6 pt-4">
                        <MomentList moments={segment.moments} compact={True}/>
                    </div>

                    <div className="px-6 pt-4 pb-8 flex flex-col gap-2">
                        {for (i, d) in enumerate(segment.dimensions) {
                            <DimensionCard key={"sd" + String(i)} dim={d} rank={i}/>
                        }}
                    </div>
                }}
            </div>
        </DrawerContent>
    </Drawer>;
}
