// DEPRECATED — superseded by widgets/kai_cortex_view.dart.
//
// This file used to hold ~150 lines: a WebView, a live RTDB knowledge-graph
// sync, a payload builder and the only setGraph() call in the codebase. All of
// it correct. All of it unreachable — NOTHING imported this file, ever.
//
// Meanwhile kai_desktop_shell built its own WebViewController for the same HTML,
// never mounted it, and never called setGraph. So the working copy was invisible
// and the visible copy was fake. That is the whole reason KaiCortexView exists:
// one widget, mounted in both places, impossible to fork again.
//
// Kept only as a redirect so any future import lands somewhere real instead of
// resurrecting the dead twin.

library;

export '../widgets/kai_cortex_view.dart' show KaiCortexScreen, KaiCortexView;
