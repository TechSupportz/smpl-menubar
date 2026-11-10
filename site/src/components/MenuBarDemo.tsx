import type React from "react";
import { Stage, States, type Act } from "../kit";
import "./menubar-demo.css";

// One display. The pointer rests on the menu bar (hidden apps appear), clicks
// the dot (everything appears), clicks it again and leaves (back to the start).

type S = { hover: boolean; click: boolean };

const initial: S = { hover: false, click: false };
const POSTER: S = { hover: true, click: true };

const REST = { wide: { x: 420, y: 360 }, compact: { x: 170, y: 270 } };

// SF Symbols rendered at 16pt; sizes are their natural boxes in points.
const SYM = {
  wifi: [21, 17],
  battery: [28, 14],
  search: [20, 19],
  control: [20, 19],
  weather: [24, 20],
  music: [14, 19],
  timer: [20, 20],
  clip: [20, 21],
  keyboard: [24, 16],
} as const;

const FILE: Record<keyof typeof SYM, string> = {
  wifi: "wifi",
  battery: "battery.100percent",
  search: "magnifyingglass",
  control: "switch.2",
  weather: "cloud.sun",
  music: "music.note",
  timer: "timer",
  clip: "paperclip",
  keyboard: "keyboard",
};

function Sym({ name }: { name: keyof typeof SYM }) {
  const [w, h] = SYM[name];
  const url = `url(/sym/${FILE[name]}.png)`;
  return (
    <span
      className="mb-sym"
      style={{ width: `${w / 16}em`, height: `${h / 16}em`, WebkitMaskImage: url, maskImage: url }}
    />
  );
}

const CAPTIONS = [
  ["Just what", "you need."],
  ["Hover for", "the rest."],
  ["Click the dot", "for everything."],
];

async function script(a: Act<S>) {
  await a.wait(1600);

  // Rest on the menu bar: hidden apps come in.
  await a.move({ at: "hover", x: 0.5, y: 0.55 });
  await a.set({ hover: true });
  await a.wait(2200);

  // Click the dot: everything.
  await a.move({ at: "dot", x: 0.62, y: 0.68 });
  await a.wait(250);
  await a.click();
  await a.set({ click: true });
  await a.wait(2600);

  // Click it again and leave: they tuck away.
  await a.click();
  await a.set({ click: false });
  await a.wait(600);
  await a.move("rest");
  await a.wait(1200);
  await a.set({ hover: false });
  await a.wait(1800);
}

export default function MenuBarDemo() {
  return (
    <Stage
      width={1120}
      height={680}
      compact={{ below: 720, width: 358, height: 400 }}
      initial={initial}
      poster={POSTER}
      script={script}
      cursor={{ at: REST, style: "large" }}
      unframed
      className="mb"
    >
      {(s, _rect, layout) => {
        const step = s.click ? 2 : s.hover ? 1 : 0;
        return (
          <div className="mb-display" data-step={step}>
            <div className="mb-bezel">
            <div className="mb-screen">
              <div className="mb-island" />
              <div className="mb-wall" data-wall="0" data-on={step === 0} />
              <div className="mb-wall" data-wall="1" data-on={step === 1} />
              <div className="mb-wall" data-wall="2" data-on={step === 2} />

              <div className="mb-bar">
                <div className="mb-bar-space" data-target="bar" />
                <div className="mb-group" data-open={s.click}>
                  <div className="mb-group-in">
                    <Sym name="clip" />
                    <Sym name="keyboard" />
                    <span className="mb-divider" />
                  </div>
                </div>
                <div className="mb-group" data-open={s.hover || s.click}>
                  <div className="mb-group-in">
                    <Sym name="weather" />
                    <Sym name="music" />
                    <Sym name="timer" />
                  </div>
                </div>
                <span className="mb-item mb-dot-hit" data-target="dot">
                  <span className="mb-dot" data-filled={!(s.hover || s.click)} />
                </span>
                <Sym name="wifi" />
                <Sym name="battery" />
                <Sym name="search" />
                <Sym name="control" />
                <span className="mb-clock">{layout === "wide" ? "Thu 6 May  9:41 AM" : "9:41 AM"}</span>
              </div>

              <div className="mb-hover" data-target="hover" />
              <div className="mb-rest" data-target="rest" />

              <div className="mb-caption">
                <States
                  value={String(step) as "0" | "1" | "2"}
                  align="end"
                  states={Object.fromEntries(
                    CAPTIONS.map(([l1, l2], i) => [String(i), <span className="mb-cap">{l1}<br />{l2}</span>]),
                  ) as Record<"0" | "1" | "2", React.ReactNode>}
                />
              </div>
            </div>
            </div>
          </div>
        );
      }}
    </Stage>
  );
}
