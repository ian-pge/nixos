fn main() {
    quickshell_brightness::main_result(|runner| {
        quickshell_brightness::output(&quickshell_brightness::brightness::run(
            &std::env::args().skip(1).collect::<Vec<_>>(),
            runner,
        )?)
    });
}
