# Rain beneath a roof window

The 1.4 rain model treats the display as a glass plane above the viewer. Drops approach nearly along the viewing direction, strike a particular point and deposit water there. The previous screen-height falling streaks are removed from the rain renderer. Snow keeps its own particle shader and movement.

Each incoming drop has a target, radius, duration and seed. A short perspective approach grows a soft, round image near that target. At contact the same event creates a brief, filled water lamella and triggers an optional quiet sound. The lamella spreads for about 55 ms, then recoils and fades into the deposited bead over about half a second. Larger contacts can leave a few tiny satellites; their volume is deducted from the central deposit. The wet pane retains and merges water, with a slight roof pitch allowing slow drainage.

Intensity changes the arrival rate of a Poisson process. It does not scale the width, length or speed of an existing drop. Drop sizes use the same distribution at every intensity. Wind affects the short approach drift. Most deposited water stays still; drain speed is capped at 2.8 logical points per second.

Experimental water-on-glass work describes an initial spreading stage and subsequent surface behavior; that provides a qualitative reference for the contact sequence. See [Dynamics of water spreading on a glass surface](https://www.sciencedirect.com/science/article/pii/S0021979704004588) and the [Drop Impact on a Solid Surface review and supplemental videos](https://www.annualreviews.org/content/journals/10.1146/annurev-fluid-122414-034401). This renderer uses deliberately readable timings and simplified optics. It does not solve fluid dynamics or reconstruct the photograph's depth or camera position.

Sixteen original damped taps are synthesized in memory. Visual contact events select a timbre and pan; intensity creates more contacts, rather than louder knocks. A bounded voice pool avoids restarting an active sound. Taps follow the ambience fade and are disabled immediately when sound or glass contact is switched off. One display supplies sound in multi-monitor sessions. The rain loop supplies diffuse background texture and has no baked-in close glass taps.

Only the app's own photograph is sampled for refraction. Desktop mode draws paired light/dark glass shading without screen capture. Turning glass off retains the short approach images and omits contact effects and collected water. Photograph softness remains bounded so the chosen view stays readable.
