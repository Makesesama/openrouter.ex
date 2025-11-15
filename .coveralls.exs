# Coveralls configuration
[
  # Skip test files from coverage
  skip_files: [
    "test/",
    "lib/mix/"
  ],

  # Coverage thresholds
  minimum_coverage: 70,

  # Stop processing after these many failures
  stop_on_failure: false,

  # Terminal output options
  terminal_options: [
    file_column_width: 40
  ]
]
