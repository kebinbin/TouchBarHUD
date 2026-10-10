# Resource use

TouchBar HUD is event driven. It has no repeating idle timer, input poll, global input monitor, or retry loop. A hidden mirror still needs the Touch Bar stream to detect display activity; stopping that stream while hidden would prevent automatic reveal.

The controller holds only the newest frame and coalesces bursts into at most 30 deliveries per second. It schedules at most one pending delivery and delivers the final frame of a burst. The view commits image changes only while visible. Activity bookkeeping runs at most four times per second. Window geometry changes only at startup, reconnect, display changes, or user alignment/model changes. The hardware-model lookup is cached once per process. One tolerant, one-shot timer handles automatic hiding.

Sleep, inactive user sessions, and loss of the built-in screen release the simulator, stream, and retained images. A wake schedules one delayed reconnect. Failed startup does not retry continuously; use the explicit Retry menu item.

## Measurements

See [VERIFICATION.md](VERIFICATION.md) for actual results and their limits. CPU percentages refer to one logical core; memory is the process's physical footprint, not the larger resident-set figure. These are process-level measurements and do not include every WindowServer, GPU, or system-wide energy cost.

## Repeat locally

Quit other Touch Bar mirrors before running a real-stream check. This starts the normal HUD using existing preferences, runs for the chosen duration, prints JSON diagnostics, and exits. It does not enable login startup or prompt for permission:

```sh
"build/TouchBar HUD.app/Contents/MacOS/TouchBarHUD" --verify-runtime 60
```

Exit status is nonzero if the stream did not become ready or another copy was already running. In another terminal, find the process PID in Activity Monitor and sample it before that duration expires:

```sh
./scripts/measure-resources.sh PID 30
```

This records interval CPU time, physical footprint samples, interrupt/package-idle wakeups, and disk I/O with `proc_pid_rusage`. It is read-only and may require execution outside a restricted sandbox.

To exercise rendering without operating the physical Touch Bar:

```sh
./scripts/stress-resources.sh
```

This creates new synthetic 2170 × 60 surfaces at 60 Hz and displays a blank strip for 45 seconds. It prints a 35-second resource sample, delivery counts, and the initial surface's release check. The fixture includes allocation/generator overhead and is not a measurement of the private backend under physical input.

Before release, also measure a 10-minute hidden idle session, Keep visible, sustained slider input, and a continuously animated Touch Bar. Check Activity Monitor's Energy tab and WindowServer alongside the app. Check stable memory over repeated show/hide, permission changes, sleep/wake, and external-display cycles. Investigate sustained idle CPU above 1% of one core, ongoing memory growth, or repeated reconnects; these are investigation thresholds rather than universal resource guarantees.
