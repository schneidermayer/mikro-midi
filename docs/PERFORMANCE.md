# Page-switch profiling

Measured on an Apple Silicon Mac running macOS 27.0.1 with the MIDI driver stopped. Each result is the median of three page visits. The same optimized Accessibility benchmark was used before and after; no sampling profiler ran during these timings.

| Page | Before, ms | After, ms |
| --- | ---: | ---: |
| Pads | 88.2 | 39.9 |
| Buttons | 222.0 | 79.2 |
| Knob | 106.3 | 83.2 |
| Touch strip | 51.7 | 36.9 |
| Setup | 64.4 | 37.8 |

These are Accessibility press-to-content-ready times, including cross-process queries and accessibility-tree traversal, not direct display-frame timings. For the Buttons page, the press call itself fell from a median 123.7 ms to 28.7 ms. Results vary by machine, system load, and window size.

A separate `sample` capture while cycling pages showed repeated SwiftUI view creation, AttributeGraph updates, and `sizeThatFits` layout work. The old conditional page switch discarded the previous page. MIDI processing was not involved in this idle reproduction.

The app now retains and prepares page hierarchies after the first frame, preserving scroll position. It uses macOS Observation and separate view boundaries so live control values update views that read them. Inactive pages are disabled, excluded from hit testing, and hidden from accessibility.

To reproduce with the app open and your terminal granted Accessibility access:

```sh
swiftc -O scripts/benchmark-tabs.swift -o /tmp/mikro-tab-benchmark
/tmp/mikro-tab-benchmark 3
```

The benchmark only switches pages; it does not change MIDI assignments.
