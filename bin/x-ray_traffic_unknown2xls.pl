#!perl

# Source: https://unix.stackexchange.com/questions/158254/convert-csv-to-xls-file-on-linux

use strict;
use Spreadsheet::WriteExcel;
use Text::CSV_XS;

# Check for valid number of arguments
if ( ( $#ARGV < 1 ) || ( $#ARGV > 2 ) ) {
    die("Usage: x-ray_traffic_unknown2xls.pl data_dir component,component\n");
}

#  /home/pmaker/network/data/dev/2022-03-10/traffic_egress_unknown_addresses.xls
#  /home/pmaker/network/data/dev/2022-03-10/traffic_egress_unknown_addresses_soa.csv
#  /home/pmaker/network/data/dev/2022-03-10/traffic_egress_unknown_addresses_mft.csv
#  /home/pmaker/network/data/dev/2022-03-10/traffic_egress_unknown_addresses_apigw.csv
#  /home/pmaker/network/data/dev/2022-03-10/traffic_egress_unknown_addresses_odi.csv

# /home/pmaker/network/data/dev/2022-03-10 soa,mft,apics,odi

my $data_dir=$ARGV[0];

my $xls_file = "${data_dir}/traffic_egress_unknown_addresses.xls";

# Create a new Excel workbook
my $workbook  = Spreadsheet::WriteExcel->new( $xls_file );

for my $component (split /,/, $ARGV[1]) {

    my $csv_file="${data_dir}/traffic_egress_unknown_addresses_${component}.csv";

    # Open the Comma Separated Variable file
    open( CSVFILE, $csv_file ) or print("Warning. Source file not found: ${csv_file}");

    my $worksheet = $workbook->add_worksheet($component);

    # Create a new CSV parsing object
    my $csv = Text::CSV_XS->new;
    # Row and column are zero indexed
    my $row = 0;
    while (<CSVFILE>) {
        if ( $csv->parse($_) ) {
            my @Fld = $csv->fields;

            my $col = 0;
            foreach my $token (@Fld) {
                $worksheet->write( $row, $col, $token );
                $col++;
            }
            $row++;
        } else {
            my $err = $csv->error_input;
            print "Text::CSV_XS parse() failed on argument: ", $err, "\n";
        }
    }
}

print("Unknown registry created:${xls_file}")
