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

# get row if column meets regexp. Replace new lines with semicolon. Requires perl and Text::CSV
function get_value_when() {
  condition_column=$1
  condition_value=$2
  column_no=$3

  perl -MText::CSV -le '$csv = Text::CSV->new({binary=>1});
    $filter=uc($ARGV[1]);
    while ($row = $csv->getline(STDIN)){ 
      s/\n/;/g for @$row;
      if (uc($row->[$ARGV[0]-1]) =~ /$filter/) {

        print($row->[$ARGV[2]-1]);
      }
    }' $condition_column "$condition_value" $column_no < $csv_file
} 

