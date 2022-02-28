#!/bin/bash


#
# CSV file helpers
#

# get csv heder
function csv_header() {
  if [ ! -f "$csv_file" ]; then
    >&2 echo "Error. CSV file not found or csv_file not defined! Set csv_file with CSV filename."
    return 1
  fi

  head -1 $csv_file
}

# get csv column number
function csv_column() {
  col_name=$1
  csv_header | tr , '\n' | nl | tr -d ' ' | tr '\t' ' '  | grep " $col_name\$" | cut -d' ' -f1
}

# get csv column numbers - sorted to use as cut parameter
function get_column_numbers() {
  columns_names=$@

  for col_name in $columns_names; do
    csv_column $col_name
  done | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//'
}

