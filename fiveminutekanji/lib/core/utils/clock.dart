/// Injectable clock so scheduling and due-counts stay deterministic in tests.
typedef Clock = DateTime Function();
