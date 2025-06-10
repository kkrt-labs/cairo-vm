use cairo_vm::cairo_run::{cairo_run, CairoRunConfig};
use cairo_vm::hint_processor::builtin_hint_processor::builtin_hint_processor_definition::BuiltinHintProcessor;
use tracing_subscriber;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing subscriber to see the structured logs
    tracing_subscriber::fmt()
        .with_target(true)
        .with_level(true)
        .init();

    // Simple Cairo program that computes fibonacci
    let program_content = std::fs::read("../cairo_programs/fibonacci.json")?;
    
    let cairo_run_config = CairoRunConfig {
        entrypoint: "main",
        trace_enabled: false,
        relocate_mem: false,
        layout: cairo_vm::types::layout_name::LayoutName::Plain,
        proof_mode: false,
        secure_run: None,
        allow_missing_builtins: None,
        dynamic_layout_params: None,
        ..Default::default()
    };

    let mut hint_processor = BuiltinHintProcessor::new_empty();
    
    println!("Running Cairo program with structured logging...");
    let runner = cairo_run(&program_content, &cairo_run_config, &mut hint_processor)?;
    
    // This will trigger our new structured logging
    let execution_resources = runner.get_execution_resources()?;
    
    println!("Execution completed successfully!");
    println!("Steps: {}", execution_resources.n_steps);
    println!("Memory holes: {}", execution_resources.n_memory_holes);
    
    Ok(())
}

