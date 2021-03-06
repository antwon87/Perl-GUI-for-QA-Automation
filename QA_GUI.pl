use strict;
use warnings;

use lib '\\\csdc\Shared\FIXTURES\Perl_libs\ActivePerl_5.24';

use 5.010;
use XML::Twig;
use File::Basename;
use File::Path qw( make_path );
use List::Util qw ( min first );
use List::MoreUtils qw( minmax uniq first_index );
use Hex::Record;
# use Cwd qw( getcwd abs_path);
use Win32::GUI();
use Win32::GUI::DropFiles;
use POSIX;
use Config::IniFiles;

# NOTE: I had to modify Hex::Record.pm line 388. It wasn't counting the end-of-line CRC in the byte count that comes after the record type.
#			Old line:     	my $byte_count = @$bytes_hex_ref + length($total_addr_hex) / 2;
#			Modified line:	my $byte_count = @$bytes_hex_ref + length($total_addr_hex) / 2 + 1;
#
#		I also added a new function to the module called GetRegions(). I'll put the code here in case my version of the module is ever lost:
			# sub GetRegions {
				# my $self = shift;
				# my @regions = ();
				
				# foreach my $part (@{$self->{parts}}) {
					# push @regions, [ $part->{start}, scalar @{$part->{bytes}} ];
				# }
				
				# return \@regions;
			# }

# PAR::Packer command line for compiling to exe: pp -M PAR -M XML::Twig -M File::Basename -M File::Path -M List::Util -M List::MoreUtils -M Hex::Record -M Win32::GUI -M POSIX -M Config::IniFiles -a checkmark_new.ico -a checkmark_new_small.ico -x -o QA_GUI.exe QA_GUI.pl
# Doesn't work very well... or at all

# TO DO: Try using IPC::Run module to run the MISP process in the background and with a timeout.
#		 Could also set up a cancel button in the log window.
#		 Win32::Process may be good for this, too.
#		 Actually, open() will allow it to run in the background. That might be good enough.

# Hide the DOS window that shows up when you start by double clicking.
# my $DOS = Win32::GUI::GetPerlWindow();
# Win32::GUI::Hide($DOS);

# TO DO: For tests that pass with a FAILED result, make sure that the test was actually run.
#		 Don't allow a FAILED result due to something like failure to read the data file get through as 
#		 a pass.
#		 I may have accomplished this, but there may be false pass scenarios I haven't caught. Something to watch out for.

# TO DO: Maybe make this compatible with MW2? Or maybe not worth it...

#####################

### MISP Variables ##

#####################

my @supported_types = ( ".bin", ".hex", ".s19", ".s29", ".s37", ".srec", ".srecord", ".mot", ".mhx" );
my %commands = ();
my %missing_commands = ();
my $misp_output = "";
my %memory_types = ();  # %memory_types{"Flash"\"EEprom"}{bank start} = bank size
my $error_count = 0;
my $QA_dir = 'C:\CheckSum\MW_QA\\';
my $modified_data_file = $QA_dir . "QA_data";
my $error_log = "";  # This string will contain all errors to be displayed at the end of the test.
my $warning_log = "";  # This string will contain all warnings to be displayed at the end of the test.
my %blank_data = ();
# Data files hash info:
#    For common data files - $data_files{$mem_type}{"Common"}[0 .. number of common data files] = $file
#	 For unique data files - $data_files{$mem_type}{"Unique"}{PCB Number} = $file
my %data_files = ();  
my $auto_detect = 0;
my $bytes_per_read = 4;
my $cancel_clicked = 0;
my @missing_addr = ();
my $max_port = 1;
my $numPCBs = 1;
my $log_file = "Better.log";
my $datafile_dir = "C:\\CheckSum\\MISP\\Fixture USBDrive\\";
my $default_datafile_dir = "C:\\CheckSum\\MISP\\Fixture USBDrive\\";
my $pps_datafile_dir = "C:\\CheckSum\\PPS\\Fixture USBDrive\\";
my %alignment = ();
my $firstUniquePCB = undef;  # First PCB with unique data. I don't know why this would ever not be 1, but let's account for it anyway.

# Create a "file handle" to the log string. This will allow me to print to the string.
# I'll open this in the Run Button event section.
# Also a file handle to the log output file.
my $to_errors;
my $to_warnings;
my $to_log_file;

#####################

##### GUI Setup #####

#####################

my $check_spacing = 90;
my $header_margin = 10;
my $body_margin = 35;
my $header_above = 15;
my $body_above = 8;

my $main = Win32::GUI::Window->new(-name => 'Main',
                                   -text => 'MultiWriter QA',
                                   -width => 600,
                                   -height => 600,
                                   -acceptfiles => 1,
                                   -onDropFiles => \&Main_DropFiles,
                                   -onResize => \&Main_Resize);

my $script_dir = (fileparse($0))[1];  # The path where QA_GUI.pl (and icons) exists
my $small_icon = new Win32::GUI::Icon($script_dir . 'checkmark_new_small.ico');
my $big_icon = new Win32::GUI::Icon($script_dir . 'checkmark_new.ico');

# my $data_dir = "$ENV{PAR_TEMP}\\inc\\"; # The path where PAR::Packer files exist.
# my $small_icon = new Win32::GUI::Icon($data_dir . 'checkmark_new_small.ico');
# my $big_icon = new Win32::GUI::Icon($data_dir . 'checkmark_new.ico');

$main->SetIcon($small_icon, 0);
$main->SetIcon($big_icon, 1);

my $log_window = Win32::GUI::Window->new(-name => 'Log',
                                         # -parent => $main,
                                         -text => 'Results',
                                         -width => $main->Width(),
                                         -height => $main->Height());
$log_window->SetIcon($small_icon, 0);
$log_window->SetIcon($big_icon, 1);

my $heading = Win32::GUI::Font->new(-bold => 1,
                                    -size => 9);

my $run_font = Win32::GUI::Font->new(-bold => 1,
                                     -size => 12);
								   
my $input_label = $main->AddLabel(-text => 'Input File',
							-top => $header_margin,
                            -left => $header_margin,
                            -font => $heading);

my $default_browse_text = "Drop or Select MISP XML file";
my $xml_browser = $main->AddTextfield(-name => 'BrowseField',
									  -text => 'C:\CheckSum\misp1.txt', ##$default_browse_text,##
									  -height => 20,
									  -width => 250,
									  -left => $body_margin,
                                      -top => $input_label->Top() + $input_label->Height() + $body_above,
                                      -foreground => [150, 150, 150]);
                                      
my $browse_button = $main->AddButton(-name => 'BrowseButton',
                              -text => 'Browse',
                              -top => $xml_browser->Top(),
							  -left => $xml_browser->Left() + $xml_browser->Width() + 5);
                            
my $config_label = $main->AddLabel(-text => 'Configuration',
							-top => $xml_browser->Top() + $xml_browser->Height() + $header_above,
                            -left => $header_margin,
                            -font => $heading);
                            
my $read_bytes = $main->AddTextfield(-name => 'Bytes',
                                     -height => 20,
                                     -width => 40,
                                     -top => $config_label->Top() + $config_label->Height() + $body_above,
                                     -left => $body_margin,
                                     -prompt => [ 'Bytes per read: ', 80 ],
                                     -text => '1',
                                     -align => 'center');
                            
my $read_updown = $main->AddUpDown(-autobuddy => 0,
                                   -setbuddy => 1,
                                   -arrowkeys => 0);
$read_updown->SetBuddy($read_bytes);
$read_updown->Range(1, 32);

my $endian = $main ->AddCheckbox(-text => 'Reverse endianness',
                                 -top => $read_bytes->Top(),
                                 -left => $read_updown->Left() + $read_updown->Width() + 25,
                                 -disabled => 1#,
								 # -checked => 1
								 );

my $full_runs = $main->AddTextfield(-name => 'FullRuns',
                                    -height => 20,
                                    -width => 55,
                                    -top => $read_bytes->Top() + $read_bytes->Height() + $body_above,
                                    -left => $body_margin,
                                    -prompt => [ 'Full sequence runs: ', 100 ],
                                    -text => '1',
                                    -align => 'center');
                            
my $full_updown = $main->AddUpDown(-autobuddy => 0,
                                   -setbuddy => 1,
                                   -arrowkeys => 0);
$full_updown->SetBuddy($full_runs);
$full_updown->Range(1, 2000);
									
my $even_odd_check = $main->AddCheckbox(-text => 'Evens/Odds test',
                                 -top => $full_runs->Top(),
                                 -left => $full_updown->Left() + $full_updown->Width() + 25
                                 # -disabled => 1
								 #-checked => 1
								 );
								 
my $append_check = $main->AddCheckbox(-text => 'Append to log',
									  -top => $full_runs->Top() + $full_runs->Height() + $body_above,
									  -left => $body_margin);
									  
my $pps_check = $main->AddCheckbox(-text => 'PPS',
								   -top => $append_check->Top(),
								   -left => $even_odd_check->Left());
								   
my $unique_check = $main->AddCheckbox(-text => 'Read unique data from all PCBs',
									  -top => $append_check->Top() + $append_check->Height() + $body_above,
									  -left => $body_margin);
									  
my $program_once_check = $main->AddCheckbox(-text => 'Program once',
										    -top => $unique_check->Top(),
											-left => $pps_check->Left());

my $commands_label = $main->AddLabel(-text => 'Supported Commands',
							-top => $unique_check->Top() + $unique_check->Height() + $header_above,
                            -left => $header_margin,
                            -font => $heading);

my $auto_check = $main->AddCheckbox(-name => 'AutoCheck',
                                    -text => 'Auto-detect from XML',
                                    -tip => "Commands present in the exported MISP step will be used for the QA.",
                                    -top => $commands_label->Top() + $commands_label->Height() + $body_above,
                                    -left => $body_margin);
                                     
my $program_check = $main->AddCheckbox(-text => '-p',
                                       -top => $auto_check->Top() + $auto_check->Height() + $body_above,
                                       -left => $auto_check->Left(),
									   #-checked => 1
									   );
                                    
my $verify_check = $main->AddCheckbox(-text => '-v',
                                      -top => $program_check->Top(),
                                      -left => $program_check->Left() + $check_spacing);
  
my $page_erase_check = $main->AddCheckbox(-text => '-e',
                                          -top => $program_check->Top(),
                                          -left => $verify_check->Left() + $check_spacing);
                                          
my $blank_check = $main->AddCheckbox(-text => '-b',
                                     -top => $program_check->Top(),
                                     -left => $page_erase_check->Left() + $check_spacing);
                                     
my $pvp_check = $main->AddCheckbox(-text => '-pvp',
                                   -top => $program_check->Top() + $program_check->Height() + $body_above,
                                   -left => $body_margin);
                                   
my $id_check = $main->AddCheckbox(-text => '-k',
                                  -top => $pvp_check->Top(),
                                  -left => $verify_check->Left());

my $chiperase_check = $main->AddCheckbox(-text => '--chiperase',
                                         -top => $pvp_check->Top(),
                                         -left => $page_erase_check->Left());
                                         
my $read_check = $main->AddCheckbox(-text => '--read',
                                    -top => $pvp_check->Top(),
                                    -left => $blank_check->Left(),
									#-checked => 1
									);
                                    
my $config_check = $main->AddCheckbox(-text => '-w',
                                      -top => $pvp_check->Top() + $pvp_check->Height() + $body_above,
                                      -left => $body_margin);
                                      
my $full_text_width = ($read_check->Left() + $read_check->Width()) - $id_check->Left();
my $default_full_text = 'Enter full sequence';
my $full_text = $main->AddTextfield(-name => 'FullField',
                                    -text => $default_full_text,
                                    -left => $verify_check->Left(),
                                    -top => $config_check->Top(),
                                    -height => 20,
                                    -width => $full_text_width,
                                    -foreground => [150, 150, 150]);
                                    
                                      
my $run_button = $main->AddButton(-name => 'Run',
                                  -text => 'QA it now',
                                  -font => $run_font,
                                  -width => 150,
                                  -height => 60);   

my $log_text = $log_window->AddTextfield(-name => 'LogText', 
                                         -readonly => 1,
                                         -text => "",
                                         -multiline => 1,
                                         -vscroll => 1);
										 
my $cancel_button = $log_window->AddButton(-name => 'Cancel',
										   -text => 'Cancel Operation');
											
my $close_button = $log_window->AddButton(-name => 'Close_Results',
										  -text => 'Close',
										  -width => $cancel_button->Width());

# my $log_file_field = $main->AddTextfield(-left => 20,
                                         # -prompt => ['Output to file:', 60],
                                         # -width => 100,
                                         # -height => 20);
                            
# my $check1 = $main->AddCheckbox(-text => 'Blue',
                                # -top => $button->Height() + $button->Top() + 5);

# my $group1 = $main->AddGroupbox(-top => 100, -height => 400, -width => 400);
# my $check2 = Win32::GUI::Checkbox->new($group1, -text => 'Check2');
# my $check3 = $group1->AddCheckbox(-text => 'Check3', -top => $check2->Top() + $check2->Height() + 5);

my $ncw = $main->Width() - $main->ScaleWidth();
my $nch = $main->Width() - $main->ScaleHeight();
my $w = $ncw + $read_check->Left() + $read_check->Width() + $body_margin;
my $h = $nch + $config_check->Top() + $config_check->Height() + $body_above + $run_button->Height() + $body_margin;
            
$main->Change(-minsize => [$w, $h]);

$main->Resize($w, $h);

my $desk = Win32::GUI::GetDesktopWindow();
my $dw = Win32::GUI::Width($desk);
my $dh = Win32::GUI::Height($desk);
my $x = ($dw - $w) / 4;
my $y = ($dh - $h) / 3;
$main->Move($x, $y);
            
$main->Show();
Win32::GUI::Dialog();

# close $to_errors;

#####################

### Window Events ###

#####################

sub Main_Terminate {
    -1;
}

sub Log_Terminate {
    $log_window->Hide();
    return 0;
}

sub BrowseButton_Click {
    # Browse for a file and place the chosen file in the text field.
    # Change the field's text color to black.
    my $text = Win32::GUI::BrowseForFolder(-editbox => 1,
                                           -includefiles => 1,
                                           -owner => $main,
                                           -directory => 'G:\CheckSum\\');
    $xml_browser->Change(-text => $text, -foreground => [0, 0, 0]) if defined $text;
    return 1;
}

sub BrowseField_GotFocus {
    # When the field gets focus, clear the default text if it is there.
    # Also set the text to black instead of the default gray.
	if ($xml_browser->Text() eq $default_browse_text) {
		$xml_browser->Change(-text => '', -foreground => [0, 0, 0]);
	}
    return 1;
}

sub BrowseField_LostFocus {
    # Put the default message with gray text back in the field if it loses
    #    focus with no text entered.
    # The "defined" bit is in there to avoid an error that occurs when 
    #    the field has focus when the window is closed.
	if (defined $xml_browser and $xml_browser->Text() eq '') {
		$xml_browser->Change(-text => $default_browse_text,
                             -foreground => [150, 150, 150]);
	}
    return 1;
}

sub FullField_GotFocus {
    # When the field gets focus, clear the default text if it is there.
    # Also set the text to black instead of the default gray.
	if ($full_text->Text() eq $default_full_text) {
		$full_text->Change(-text => '', -foreground => [0, 0, 0]);
	}
    return 1;
}

sub FullField_LostFocus {
    # Put the default message with gray text back in the field if it loses
    #    focus with no text entered.
    # The "defined" bit is in there to avoid an error that occurs when 
    #    the field has focus when the window is closed.
	if (defined $full_text and $full_text->Text() eq '') {
		$full_text->Change(-text => $default_full_text,
                             -foreground => [150, 150, 150]);
	}
    return 1;
}

sub Bytes_Change {
    # Disable the endianness check box if only reading one byte at a time
    if ($read_bytes->Text() eq '1') {
        $endian->Disable();
    } else {
        $endian->Enable();
    }
    return 1;
}

sub AutoCheck_Click {
    # Disable command check boxes if auto-detecting
    if ($auto_check->Checked()) {
        $program_check->Disable();
        $verify_check->Disable();
        $page_erase_check->Disable();
        $blank_check->Disable();
        $pvp_check->Disable();
        $id_check->Disable();
        $chiperase_check->Disable();
        $read_check->Disable();
        $config_check->Disable();
        # $full_text->Disable();
    } else {
        $program_check->Enable();
        $verify_check->Enable();
        $page_erase_check->Enable();
        $blank_check->Enable();
        $pvp_check->Enable();
        $id_check->Enable();
        $chiperase_check->Enable();
        $read_check->Enable();
        $config_check->Enable();
        # $full_text->Enable();
    }
    
    return 1;
}

sub Run_Click {
    # Do the thing
    
    my $xml_trimmed = $QA_dir . 'misp_qa_xml_only.xml';
    my $xml_out = $QA_dir . 'misp_qa_2.xml';
    my $xml_verify = $QA_dir . 'verify_op.xml';
    my @test_result = ();
    my $read_size_max = 16;
    my %addresses = ();  # $addresses{$mem_type}{top/bottom/mid}{file/addr}; Value for key "file" is the file in which to find the addresses.
						 #											  Value for key "addr" is the addresses.
    my %read_once = ();
    $auto_detect = $auto_check->Checked();
    my $reverse_endian = $endian->Checked();
    $bytes_per_read = $read_bytes->Text(); 
    my $full_sequence = $full_text->Text();
	my $full_num = $full_runs->Text();
	my $even_odd = $even_odd_check->Checked();
	my $append = $append_check->Checked();
	my $unique_test_all = $unique_check->Checked();
	my $program_once = $program_once_check->Checked();
	$max_port = 1;
	my $num_MWs = 1;
	$datafile_dir = $pps_check->Checked() ? $pps_datafile_dir : $default_datafile_dir;
	$cancel_clicked = 0;
	@missing_addr = ();
    $error_log = "";
	$warning_log = "";
	$error_count = 0;
    %missing_commands = ();
    %memory_types = ();
    %blank_data = ();
    %data_files = ();
    %commands = ();
	$firstUniquePCB = undef;
    
    # Clear the log window for a new run. Maybe...
    $log_text->Change(-text => '');
    
    # Show the log window if it is not already shown.
    if (not $log_window->IsVisible()) {
        $log_window->Resize($w, $h);
        $log_window->Move($main->Left() + 20, $main->Top() + 20);
        # $log_text->Change(-height => $log_window->ScaleHeight() - 10 - $cancel_button->Height() - 100,
                          # -width => $log_window->ScaleWidth() - 10,
                          # -top => 5,
                          # -left => 5);
        $log_window->Show();
    }
	$log_window->BringWindowToTop();

    # Create a directory for the QA files if it doesn't already exist.
    make_path $QA_dir if not -d $QA_dir;
    
    # Open the "file handle" for printing to the log strings and file handle for the log file.
    open $to_errors, '>>', \$error_log or die "Can't open \$to_errors: $!\n";
	open $to_warnings, '>>', \$warning_log or die "Can't open \$to_warnings: $!\n";
	if ($append) {
		open $to_log_file, '>>', $QA_dir . $log_file or die "Couldn't open file '$QA_dir$log_file'. $!\n";
	} else {
		open $to_log_file, '>', $QA_dir . $log_file or die "Couldn't open file '$QA_dir$log_file'. $!\n";
	}
    
    # Set up commands hash if not auto-detecting commands.
    if (not $auto_detect) {
        $commands{"-p"} = "program" if $program_check->Checked();
        $commands{"-v"} = "verify" if $verify_check->Checked();
        $commands{"-e"} = "erase" if $page_erase_check->Checked();
        $commands{"-b"} = "blank" if $blank_check->Checked();
        $commands{"-pvp"} = "pvp" if $pvp_check->Checked();
        $commands{"-k"} = "id" if $id_check->Checked();
        $commands{"--chiperase"} = "erase" if $chiperase_check->Checked();
        $commands{"--read"} = "read" if $read_check->Checked();
        $commands{"-w"} = "config" if $config_check->Checked();
    }
    $commands{$full_sequence} = "full";

    my $xml_raw = $xml_browser->Text();
    die "ERROR: You must include the XML file exported from the MISP step.\n" if $xml_raw eq $default_browse_text;
	# TO DO: Enable below line.
    # die "ERROR: You must set a full programming sequence.\n" if $full_sequence eq $default_full_text;

    # Delete all files generated by this script prior to running anew. Except the log file if set to append.
	if ($append_check->Checked()) {
		unlink grep { !/$log_file/ } glob $QA_dir . "*";
	} else {
		unlink glob $QA_dir . "*";
	}

    #-------------------#

    #---- Clean XML ----#

    #-------------------#
    # Wiring and other info is included at the end of the XML file exported from the MISP step.
    # Remove it before processing the XML, as it is unnecessary for this QA process.

    open(my $infile, '<', $xml_raw) or die "ERROR: Couldn't open input XML file.\n";
    open(my $outfile, '>', $xml_trimmed) or die "ERROR: Couldn't open file to output trimmed XML.\n";

    while (<$infile>) {
        print $outfile $_;
        if ($_ =~ m/<\/MultiWriters>/) {
            last;
        }
    }

    close $infile;
    close $outfile;

    #-------------------#

    #---- Parse XML ----#

    #-------------------#

    my $twig = new XML::Twig( twig_handlers => { Command => \&AddCommand,
                                                 verbosity => \&SetVerbosity,
                                                 blankdata => \&BlankData,
                                                 Bank => \&AddBanks,
                                                 DataFile => \&AddDataFiles,
												 logfile => \&SetLogFile,
												 dev => \&PortCount,
												 alignment => \&SetAlignment } );

    $twig->parsefile($xml_trimmed);
    my $root = $twig->root;

    # EX
    # my $child = $field->first_child("Command");
    # print $child if defined $child;

    # EX
    # my $id = $root->next_elt("devId")->text;
    # my $new_id = sprintf("%#x", 1 + hex $id);  # '#' makes the 0x
    # print "$new_id \n";

    $twig->print_to_file($xml_out, PrettyPrint => "indented" );


    # die "that's all for now!\n";

    #-------------------#

    #---- MISP Setup ---#

    #-------------------#

	# Calculate number of MW cards from highest active port.
	$num_MWs = ceil($max_port / 24);
	my $self_test_string = "--diag 1";
	$self_test_string .= "-$num_MWs" if $num_MWs > 1;
	$commands{$self_test_string} = 1;
	
    # If there is a read or verify command, set up addresses for top and bottom of part.
    if ((not exists $commands{"--read"}) && (not exists $commands{"-v"})) {
            $missing_commands{"--read"} = 1;
			$missing_commands{"-v"} = 1;
            # $log_text->Append("WARNING: No --read command in MISP setup. Related tests skipped. \r\n");
            # $log_text->Append("WARNING: No -v command in MISP setup. Related tests skipped. \r\n");
			print $to_warnings "WARNING: No --read command in MISP setup. Related tests skipped. \r\n";
			print $to_warnings "WARNING: No -v command in MISP setup. Related tests skipped. \r\n";
    } else {
        foreach my $mem_type (keys %memory_types) {
            # Find the bank with the lowest and the bank with the highest addresses
			my @banks = sort { $a <=> $b } keys %{$memory_types{$mem_type}};
			
			# Read twice as many bytes if the alignment is 2, so that you are reading the specified number of words.
			# This is, of course, assuming that all word-addressed parts have 16-bit words, which I doubt, but people tell me it's true.
			my $read_size = ($alignment{$mem_type} == 1) ? $read_size_max : $read_size_max * 2;
			my $size = 0;
            # my ($min_bank, $max_bank) = minmax keys %{$memory_types{$mem_type}};
			
			# If there is no data file associated with this memory type, just use the extreme ends of the memory space.
			if (not exists $data_files{$mem_type}{"Common"}) {
				$size = $memory_types{$mem_type}{$banks[0]};

				# If a bank is smaller than the default number of bytes to read, only read as many
				#   bytes as there are. If that small bank is the only bank, don't bother reading it twice.
				if ($size <= $read_size) {
					$read_size = $size;
					$read_once{$mem_type} = 1 if $banks[0] == $banks[-1];
				}
				
				# Set up hash containing addresses to read at the top of the memory type.
				$addresses{$mem_type}{"top"}{"addr"} = [$banks[0] .. $banks[0] + $read_size - 1];
			
				# Don't read the bottom of the memory if the top covered the whole thing. Unlikely... but let's check anyway.
				next if ($read_once{$mem_type});

				# Reset variables
				$read_size = ($alignment{$mem_type} == 1) ? $read_size_max : $read_size_max * 2;
				$size = $memory_types{$mem_type}{$banks[-1]};
				$read_size = $size if ($size < $read_size);
				
				# Set up hash containing addresses to read at the bottom of the memory type.
				$addresses{$mem_type}{"bottom"}{"addr"} = [$banks[-1] + $size - $read_size .. $banks[-1] + $size - 1];
			} else {
				# Search through all known data files to find which contains the lowest address.
				# Right now, this just looks for a file that has the lowest address, but not the whole range to be read.
				# Iterates through all addresses in all banks starting at the lowest.
				TOP_SEARCH: for my $bank (@banks) {
					$size = $memory_types{$mem_type}{$bank};
					for my $addr ($bank .. $bank + $size - 1) {
						# If alignment 2, change from physical bank address to byte address.
						$addr *= 2 if $alignment{$mem_type} == 2;
						for my $file (@{$data_files{$mem_type}{"Common"}}) {
							if (IsAddrInFile($addr, $file, $mem_type) == 1) {
								$addresses{$mem_type}{"top"}{"file"} = $file;
								# Don't overflow the bank if the start address is near its end.
								$read_size = $bank + $size - $addr if $addr + $read_size > $bank + $size;
								$addresses{$mem_type}{"top"}{"addr"} = [$addr .. $addr + $read_size - 1];
								# Don't do a bottom read if this read will somehow cover the end of the memory space.
								$read_once{$mem_type} = 1 if ($addresses{$mem_type}{"top"}{"addr"}[-1] == $bank + $size - 1);
								last TOP_SEARCH;
							}
						}
					}
				}
			
				# Don't read the bottom of the memory if the top covered the whole thing. Unlikely... but let's check anyway.
				# Also set the "bottom" address to the last in the top array. This will only be used when finding a middle address for verify.
				if ($read_once{$mem_type}) {
					$addresses{$mem_type}{"bottom"}[0] = $addresses{$mem_type}{"top"}[-1];
					next;
				}

				$read_size = ($alignment{$mem_type} == 1) ? $read_size_max : $read_size_max * 2;
				
				# Search through all known data files to find which contains the highest address.
				# Right now, this just looks for a file that has the highest address, but not the whole range to be read.
				# Iterates through all addresses in all banks starting at the highest.
				BOT_SEARCH: for my $bank (reverse @banks) {
					$size = $memory_types{$mem_type}{$bank};
					for my $addr (reverse $bank .. $bank + $size - 1) {
						# If alignment 2, change from physical bank address to byte address.
						$addr = ($addr * 2) + 1 if $alignment{$mem_type} == 2;
						for my $file (@{$data_files{$mem_type}{"Common"}}) {
							if (IsAddrInFile($addr, $file, $mem_type) == 1) {
								$addresses{$mem_type}{"bottom"}{"file"} = $file;
								# Don't underflow the bank if the start address is near its beginning.
								$read_size = $addr - $bank + 1 if $addr - $bank + 1 < $read_size;
								$addresses{$mem_type}{"bottom"}{"addr"} = [$addr - $read_size + 1 .. $addr];
								last BOT_SEARCH;
							}
						}
					}
				}
			
				# Error if no address was found in any data file. Something must be seriously wrong for this to happen, but let's check for it anyway.
				if ((not exists $addresses{$mem_type}{"top"}{"file"}) || (not exists $addresses{$mem_type}{"bottom"}{"file"})) {
					print $to_errors "ERROR: Unable to find any bank addresses in data files from XML. Hopefully nobody ever sees this.\r\n";
				}
			}
        }
    }
	
    # If there is a verify command, set up a middle address to modify.
    if (not exists $commands{"-v"}) {
        if (not exists $missing_commands{"-v"}) {
            $missing_commands{"-v"} = 1;
            # $log_text->Append("\r\nWARNING: No -v command in MISP setup. Related tests skipped. \r\n");
			print $to_warnings "WARNING: No -v command in MISP setup. Related tests skipped. \r\n";
        }
    } else {
        foreach my $mem_type (keys %memory_types) {
			my @banks = sort { $a <=> $b } keys %{$memory_types{$mem_type}};
			
            # Skip this memory type if there is no associated data file. Or if it is so small we are only doing one read.
            next if ((not exists $data_files{$mem_type}{"Common"}) || ($read_once{$mem_type}));
			
			# Storage for the address in the middle of the memory space.
			my $mid_addr = 0;
            
            # Iterate through banks to find what address will be the middle.
            my $count = 0;
            foreach my $bank (@banks) {
				my $size = $memory_types{$mem_type}{$bank};
				
				# Move along if the "top" address is above this whole bank. We already know things below the "top" are not in the data files.
				next if ($bank + $size - 1 < $addresses{$mem_type}{"top"}{"addr"}[0]);
				# Stop looking if you've gone past the "bottom" address. We already know anything left is not in the data files.
				last if ($bank > $addresses{$mem_type}{"bottom"}{"addr"}[-1]);
				
				# Loop through all addresses of this bank to find the number of addresses between the "top" and "bottom".
				foreach my $addr ($bank .. $bank + $size - 1) {
					# Increment $count if the current address is between the "top" and "bottom".
					$count++ if (($addr >= $addresses{$mem_type}{"top"}{"addr"}[0]) && ($addr <= $addresses{$mem_type}{"bottom"}{"addr"}[-1]));
				}
            }
			
			# $count now contains the number of addresses between the "top" and "bottom" addresses.
			# Now I need to find the address in the middle of this.
			$count = floor($count / 2);
			MID_ADDR_SEARCH: foreach my $bank (@banks) {
				my $size = $memory_types{$mem_type}{$bank};
				
				# Move along if the "top" address is above this whole bank.
				next if ($bank + $size - 1 < $addresses{$mem_type}{"top"}{"addr"}[0]);
				
				# Loop through all addresses of this bank, decrementing $count for each address between "top" and "bottom".
				foreach my $addr ($bank .. $bank + $size - 1) {
					$count-- if (($addr >= $addresses{$mem_type}{"top"}{"addr"}[0]) && ($addr <= $addresses{$mem_type}{"bottom"}{"addr"}[-1]));
					if ($count <= 0) {
						$mid_addr = $addr;
						last MID_ADDR_SEARCH;
					}
				}
			}
			
			# Now... find the nearest address that is actually in a data file.
			# I think this would be cool if it could search for the closest real address in either direction,
			# but I'm just going to look for the next closest higher address for now.
			MID_SEARCH: for my $bank (@banks) {
				my $size = $memory_types{$mem_type}{$bank};  # Skip banks until finding the one with mid in it.
			    next if $bank + $size - 1 < $mid_addr;
				for my $addr ($bank .. $bank + $size - 1) {
					next if $addr < $mid_addr;  # Skip addresses until reaching the mid address.
					for my $file (@{$data_files{$mem_type}{"Common"}}) {
						if (IsAddrInFile($addr, $file, $mem_type) == 1) {
							$addresses{$mem_type}{"mid"}{"file"} = $file;
							$addresses{$mem_type}{"mid"}{"addr"} = [$addr];
							last MID_SEARCH;
						}
					}
				}
			}
        }
    }
	
	#-------------------#

    #-- MW Self-test  --#

    #-------------------#

	$log_text->Append("Running MW3 self-test...\r\n");
	@test_result = RunMISP($self_test_string, $xml_out);
	Cleanup() if $cancel_clicked;
	return 1 if $cancel_clicked;
	print $to_log_file FormatHeader("MW Self-test") . $misp_output;
	$log_text->Append("\tSelf-test: $test_result[0]\r\n");
	if ($test_result[0] eq "FAILED") {
		print $to_errors "ERROR: MultiWriter self-test failed.\r\n";
		$error_count++;
	}

    #-------------------#

    #---- ID Tests  ----#

    #-------------------#

    if (not exists $commands{"-k"}) {
        $missing_commands{"-k"} = 1;
        # $log_text->Append("\r\nWARNING: No -k command in MISP setup. ID check skipped. Does this chip have an ID? \r\n");
		print $to_warnings "WARNING: No -k command in MISP setup. ID check skipped. Does this chip have an ID? \r\n";
    } else {
        # First test uses base XML file, presumably with the correct device ID
        $log_text->Append("\r\nRunning ID tests...\r\n");

        @test_result = RunMISP("-k", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Proper ID") . $misp_output;
        $log_text->Append("\tTest with proper ID: $test_result[0]\r\n");
        if ($test_result[0] eq "FAILED") {
            print $to_errors "ERROR: Device ID test failed with given ID.\r\n";
            $error_count++;
        }

        # Second test uses modified XML file with an altered device ID
        # Begin by setting up the new XML file
        my $field = $root->next_elt("devId");
        my $id = $field->text;
        my $new_id = sprintf("%#x", 42 + hex $id);  # '#' makes the 0x
        $field->set_text($new_id);
        $twig->print_to_file($xml_out, PrettyPrint => "indented" );

        # Now run the test
        @test_result = RunMISP("-k", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("False ID") . $misp_output;
        $log_text->Append("\tTest with wrong ID: " . ($test_result[0] eq "FAILED" ? "PASSED" : "FAILED") . "\r\n");
        if ($test_result[0] eq "PASSED") {
            print $to_errors "ERROR: Device ID test passed with altered ID.\r\n";
            $error_count++;
        }
    }

    #-------------------#

    #--- Erase Tests ---#

    #-------------------#

    if ((not exists $commands{"--chiperase"}) && (not exists $commands{"-e"})) {
        $missing_commands{"--chiperase"} = 1;
        $missing_commands{"-e"} = 1;
		# $log_text->Append("\r\nWARNING: No chip erase command in MISP setup. Blank tests skipped. Can this chip be erased? \r\n");
		print $to_warnings "WARNING: No chip erase command in MISP setup. Blank tests skipped. Can this chip be erased? \r\n";
        
    } else {
        # Erase the chip
        $log_text->Append("\r\nRunning erase tests...\r\n");
        
        my $erase_command = (exists $commands{"--chiperase"} ? "--chiperase" : "-e");
        @test_result = RunMISP($erase_command, $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Erase") . $misp_output;
        $log_text->Append("\tErase operation: $test_result[0]\r\n");
        if ($test_result[0] eq "FAILED") {
            print $to_errors "ERROR: Chip erase failed.\r\n";
            $error_count++;
        }
        
        # Do a blank check
        @test_result = RunMISP("-b", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Blank after erase") . $misp_output;
		$test_result[0] = "SKIPPED" if $test_result[0] eq "NO_COMMAND";
        $log_text->Append("\tBlank check while blank: $test_result[0]\r\n");
        if ($test_result[0] eq "FAILED") {
            print $to_errors "ERROR: Blank check failed. Chip not blank after erase.\r\n";
            $error_count++;
        }
        
        # Do a verify
        @test_result = RunMISP("-v", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Verify after erase") . $misp_output;
		if ($test_result[0] eq "NO_COMMAND") {
			$log_text->Append("\tVerify while blank: SKIPPED\r\n");
		} else {
			$log_text->Append("\tVerify while blank: " . ($test_result[0] eq "FAILED" ? "PASSED" : "FAILED") . "\r\n");
		}
        if ($test_result[0] eq "PASSED") {
            print $to_errors "ERROR: Verify succeeded after erase.\r\n";
            $error_count++;
        }
        
        # Do read tests, unless there is no --read command in the setup.
        if (exists $commands{"--read"}) {
			print $to_log_file FormatHeader("Reads after erase");
            foreach my $mem_type (keys %memory_types) {
				my %read_errors = ();
				my $read_totally_failed = 0;
				foreach my $region ("top", "bottom") {					
					print $to_log_file "----------\nRead $region\n----------\n";
					
					# Make a string containing the range of addresses to read and the memory type to read from.
					# If alignment is 2, need to translate the hex file byte addresses into physical word addresses by dividing by 2.
					my $range = "";
					if ($alignment{$mem_type} == 1) {
						$range = sprintf("%#x-%#x %s", $addresses{$mem_type}{$region}{"addr"}[0], $addresses{$mem_type}{$region}{"addr"}[-1], $mem_type); 
					} else {
						# The physical address will be the byte address divided by two, and only have 1 physical for every other byte.
						my @physical_addresses = map {$_ % 2 == 0 ? $addresses{$mem_type}{$region}{"addr"}[$_] / 2 : ()} (0 .. $#{$addresses{$mem_type}{$region}{"addr"}});
						$range = sprintf("%#x-%#x %s", $physical_addresses[0], $physical_addresses[-1], $mem_type);
					}
					RunMISP("--read", $xml_out, $range);  # Read from the memory region
					Cleanup() if $cancel_clicked;
					return 1 if $cancel_clicked;
					print $to_log_file $misp_output;
					
					# Throw the data returned from all addresses into an array.
					my @data = $misp_output =~ m/Device Memory.*=\s(.*)/g;
					
					if (scalar @data == 0) {
						print $to_errors "ERROR: No data was able to be read from the $region of the part.\r\n";
						$read_totally_failed = 1;
						$error_count++;
					}
					
					# If the alignment is 1, but the blank data was entered sloppily in the XML, it may need some massaging.
					# I'm going to hope that alignment 2 parts never have sloppy blank data.
					if ($alignment{$mem_type} == 1) {
						# Adjust the blank data to have the same number of bytes as are output when reading an address.
						# $len_dif is the length difference in characters.
									# 2 chars per byte + 2 for 0x
						my $len_dif = ($bytes_per_read * 2 + 2) - (length $blank_data{$mem_type});
						if ($len_dif > 0) {
							# Duplicate blank data until the string is the right length.
							# This will likely be problematic if the blank data is not an integer number of bytes, but I'm going to hope that never happens.
							$blank_data{$mem_type} .= substr($blank_data{$mem_type}, 2, 2) x ($len_dif / 2);
						} elsif ($len_dif < 0) {
							# Crop off the end of the blank data string
							$blank_data{$mem_type} = substr($blank_data{$mem_type}, 0, (length $blank_data{$mem_type}) + $len_dif);
						}
					}
					
					# Check to make sure the array only contains correct data.
					foreach my $i (0 .. $#data) {
						$read_errors{$addresses{$mem_type}{$region}{"addr"}[$i]} = $data[$i] if hex $data[$i] != hex $blank_data{$mem_type};
					}
					
					# Skip bottom read if it was covered by the top read.
					last if $read_once{$mem_type};
				}
			
				# Display read errors if any occurred.
				if ($read_totally_failed) {
					$log_text->Append("\tRead blank data ($mem_type): FAILED\r\n");
                } elsif (scalar (keys %read_errors)) {
                    $log_text->Append("\tRead blank data ($mem_type): FAILED\r\n");
                    print $to_errors "ERROR: Blank data read failed at address " . sprintf("%#x", $_) . " of $mem_type.\r\n" . 
                    "    Data read was $read_errors{$_}.\r\n" foreach (sort { $a <=> $b } keys %read_errors);
					$error_count += scalar keys %read_errors;
                } else {
                    $log_text->Append("\tRead blank data ($mem_type): PASSED\r\n");
                }
            }
        }
    }

    #-------------------#

    #-- Program Tests --#

    #-------------------#

    if (not exists $commands{"-p"}) {
        $missing_commands{"-p"} = 1;
		# $log_text->Append("\r\nWARNING: No -p command in MISP setup. Programming tests skipped. Can this chip be programmed? \r\n");
		print $to_warnings "WARNING: No -p command in MISP setup. Programming tests skipped. Can this chip be programmed? \r\n";
    } else {
        # Program the chip
        $log_text->Append("\r\nRunning programming tests...\r\n");
        
        @test_result = RunMISP("-p", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Program") . $misp_output;
        $log_text->Append("\tProgram operation: $test_result[0]\r\n");
        if ($test_result[0] eq "FAILED") {
            print $to_errors "ERROR: Programming failed.\r\n";
            $error_count++;
        }
        
        # Program it again to make sure you can program a pre-programmed chip
		if ($program_once != 1) {
			@test_result = RunMISP("-p", $xml_out);
			Cleanup() if $cancel_clicked;
			return 1 if $cancel_clicked;
			print $to_log_file FormatHeader("Program again") . $misp_output;
			$log_text->Append("\tProgram while already programmed: $test_result[0]\r\n");
			if ($test_result[0] eq "FAILED") {
				print $to_errors "ERROR: Programming failed when the chip is already programmed.\r\n";
				$error_count++;
			}
		}
        
        # Do a blank check
        @test_result = RunMISP("-b", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Blank after program") . $misp_output;
		if ($test_result[0] eq "NO_COMMAND") {
			$log_text->Append("\tBlank check while programmed: SKIPPED\r\n");
		} else {
			$log_text->Append("\tBlank check while programmed: " . ($test_result[0] eq "FAILED" ? "PASSED" : "FAILED") . "\r\n");
		}
        if ($test_result[0] eq "PASSED") {
            print $to_errors "ERROR: Blank check passed. Chip blank after programming.\r\n";
            $error_count++;
        }
        
        # Do a verify
        @test_result = RunMISP("-v", $xml_out);
		Cleanup() if $cancel_clicked;
		return 1 if $cancel_clicked;
		print $to_log_file FormatHeader("Verify after program") . $misp_output;
		$test_result[0] = "SKIPPED" if $test_result[0] eq "NO_COMMAND";
        $log_text->Append("\tVerify while programmed: $test_result[0]\r\n");
		
        if ($test_result[0] eq "FAILED") {
            print $to_errors "ERROR: Verify failed after programming.\r\n";
            $error_count++;
        }
        
        # If the verify command exists, modify bytes in the data file to verify verify.
        if (not exists $missing_commands{"-v"}) {
			print $to_log_file FormatHeader("Verify with modified data file");
        
            foreach my $mem_type (keys %memory_types) {
                # Skip this memory type if there is no associated data file.
                next if (not exists $data_files{$mem_type}{"Common"});
                
                # Modify a byte at each of the top, middle, and bottom.
                foreach my $region (keys %{$addresses{$mem_type}}) {    
					print $to_log_file "----------\nVerify $region\n----------\n";
					
					# Skip this region if there is no associated data file. I don't think this should ever happen
					# due to the way that I search for a file in the MISP setup section.
					next if not exists $addresses{$mem_type}{$region}{"file"};
					
					# Find the current data file field in the XML.
					my $elt = $root->next_elt("CommonData")->first_child("DataFile");
					while (defined $elt) { # && $elt->first_child("RecentFilePath")->text() ne $addresses{$mem_type}{$region}{"file"}) {
						my $xml_file = $elt->first_child("RecentFilePath")->text();
						# Tack on the full path if the XML has a relative path, to match what I've stored in %addresses.
						$xml_file = $datafile_dir . substr($xml_file, 2) if (substr($xml_file, 0, 1) eq ".");
						last if $xml_file eq $addresses{$mem_type}{$region}{"file"};
						$elt = $elt->next_sibling("DataFile");
					}
					
					# Skip this region if the data file containing the region was not found in the xml.
					# This should NEVER happen. If it does, something is wrong with this script.
					if (not defined $elt) {
						print $to_warnings "WARNING: Data file for the $region region, $addresses{$mem_type}{$region}{\"file\"}, was not found in the XML.\r\n";
						next;
					}
										
					# Change XML to use the modified data file.
					my $extension = lc +(fileparse($addresses{$mem_type}{$region}{"file"}, @supported_types))[2];
					my $new_path = $modified_data_file . $extension;
					$elt->first_child("RecentFilePath")->set_text($new_path);
					$twig->print_to_file($xml_verify, PrettyPrint => "indented" );
					
                    # Read the current byte.
                    my $temp_data = ReadDataFile($addresses{$mem_type}{$region}{"file"}, $mem_type, $addresses{$mem_type}{$region}{"addr"}[0], 1);
                    
                    # Increment said byte and store it as a string again. Skip if it wasn't found in the data file.
					if ((defined $$temp_data[0]) && ($$temp_data[0] ne "not found")) {
						$$temp_data[0] = hex $$temp_data[0] == 255 ? 0 : (hex $$temp_data[0]) + 1;
						$$temp_data[0] = sprintf("%02x", $$temp_data[0]);
                    
						# Write modified byte to new file. The data structure in memory will be restored to the previous
						#   state after writing out the modified file.
						WriteDataFile($addresses{$mem_type}{$region}{"file"}, $mem_type, $addresses{$mem_type}{$region}{"addr"}[0], $temp_data);
						
						# Verify with the modified file, expecting a failure.
						@test_result = RunMISP("-v", $xml_verify);
						Cleanup() if $cancel_clicked;
						return 1 if $cancel_clicked;
						print $to_log_file $misp_output;
						$log_text->Append("\tVerify with modified data file ($mem_type $region): " . ($test_result[0] eq "FAILED" ? "PASSED" : "FAILED") . "\r\n");
						if ($test_result[0] eq "PASSED") {
							print $to_errors "ERROR: Verify passed after modifying address $addresses{$mem_type}{$region}{\"addr\"}[0] in the data file.\r\n";
							$error_count++;
						}
					}
                
					# Restore the XML file to the original data file.
					$elt->first_child("RecentFilePath")->set_text($addresses{$mem_type}{$region}{"file"});
                }
            }
        }
        
        #----- Config Word Test -----#
        
        # Write config words if a -w command exists in the XML
        if (exists $commands{"-w"}) {
            @test_result = RunMISP("-w", $xml_out);
			Cleanup() if $cancel_clicked;
			return 1 if $cancel_clicked;
			print $to_log_file FormatHeader("Write config words") . $misp_output;
            $log_text->Append("\tWrite config words: $test_result[0]\r\n");
            if ($test_result[0] eq "FAILED") {
                print $to_errors "ERROR: Config word write failed.\r\n";
                $error_count++;
            }
        }
        
        #----- Read Test -----#
        
        # Do read top/bottom tests, unless there is no --read command in the setup. Also do device-specific-data test if necessary.
        if (exists $commands{"--read"}) {
			print $to_log_file FormatHeader("Read after programming");
            foreach my $mem_type (keys %memory_types) {
                # Skip this memory type if there is no associated data file.
                next if (not exists $data_files{$mem_type}{"Common"});
			
				my %read_errors = ();	
				my $read_totally_failed = 0;
				
				foreach my $region ("top", "bottom") {
					print $to_log_file "----------\nRead $region\n----------\n";
				
					# Make a string containing the range of addresses to read and the memory type to read from.
					# If alignment is 2, need to translate the hex file byte addresses into physical word addresses by dividing by 2.
					my $range = "";
					if ($alignment{$mem_type} == 1) {
						$range = sprintf("%#x-%#x %s", $addresses{$mem_type}{$region}{"addr"}[0], $addresses{$mem_type}{$region}{"addr"}[-1], $mem_type); 
					} else {
						# The physical address will be the byte address divided by two, and only have 1 physical for every other byte.
						my @physical_addresses = map {$_ % 2 == 0 ? $addresses{$mem_type}{$region}{"addr"}[$_] / 2 : ()} (0 .. $#{$addresses{$mem_type}{$region}{"addr"}});
						$range = sprintf("%#x-%#x %s", $physical_addresses[0], $physical_addresses[-1], $mem_type);
					}
					
					RunMISP("--read", $xml_out, $range);  # Read from the top of the memory
					print $to_log_file $misp_output;
					Cleanup() if $cancel_clicked;
					return 1 if $cancel_clicked;
					
					# Throw the data returned from all addresses into an array.
					my @data = $misp_output =~ m/Device Memory.*= 0x([0-9a-fA-F]*)/g; # m/Device Memory.*=\s(.*)/g;
					
					if (scalar @data == 0) {
						print $to_errors "ERROR: No data was able to be read from the $region of the part.\r\n";
						$read_totally_failed = 1;
						$error_count++;
					}
					
					# Read the addresses from the data file. Arguments are the data file, the starting address, and the length of the address array.
					my @good_data = @{ReadDataFile($addresses{$mem_type}{$region}{"file"}, $mem_type, $addresses{$mem_type}{$region}{"addr"}[0], scalar @{$addresses{$mem_type}{$region}{"addr"}})};
					if ($alignment{$mem_type} == 2) {
						# If alignment is 2, shift data about to make word strings that will match the MISP output.
						if ($reverse_endian) {  # I'm assuming "reverse endian" is big endian. It's poorly named, but deal with it.
							my @index = map {$_ * 2} (0 .. ($#{$addresses{$mem_type}{$region}{"addr"}} - 1) / 2);  # Set up array with all even indices in the address array.
							@good_data = map {sprintf("0x%02x%02x", hex $good_data[$_], hex $good_data[$_ + 1])} @index;
						} else {  # Little endian.
							my @index = map {$_ * 2 + 1} (0 .. ($#{$addresses{$mem_type}{$region}{"addr"}} - 1) / 2);  # Set up array with all odd indices in the address array.
							@good_data = map {sprintf("0x%02x%02x", hex $good_data[$_], hex $good_data[$_ - 1])} @index;
						}
					}
					
					if ($good_data[0] eq "ERROR") {
						print $to_errors "ERROR: Unable to read from data file '$addresses{$mem_type}{$region}{\"file\"}' for read test.\r\n";
						next;
					}

					# If the alignment is 1 and the algorithm author was lazy, mask bytes as needed.
					if ($alignment{$mem_type} == 1 && $bytes_per_read > 1) {
						# Pick out the proper byte if there are multiple bytes reported for each address. Pad with leading 0's first.
						foreach my $i (0 .. $#data) {
							$data[$i] = sprintf("%0" . (2 * $bytes_per_read) . "x", hex $data[$i]) if (length $data[$i] < (2 * $bytes_per_read));
							my $offset = ($i % $bytes_per_read) * 2;
							$offset = ($bytes_per_read * 2) - $offset - 2 if $reverse_endian;
							$data[$i] = substr($data[$i], $offset, 2);
						}
					}
					
					# printf("%d %d\r\n", hex $data[$_], hex $good_data[$_]) foreach (0 .. $#data);
					
					# Check to make sure the array only contains correct data.
					foreach my $i (0 .. $#data) {
						# Skip the good data comparison if the address was not found in the data file
						if ((defined $good_data[$i]) && ($good_data[$i] ne "not found")) {
							$read_errors{$addresses{$mem_type}{$region}{"addr"}[$i]} = $data[$i] if hex $data[$i] != hex $good_data[$i];
						}
					}
					
					# Skip bottom read if it was covered by the top read.
					last if exists $read_once{$mem_type};
				}
				                
                # Display read errors if any occurred.
                if ($read_totally_failed) {
					$log_text->Append("\tRead programmed data ($mem_type): FAILED\r\n");
				} elsif (scalar (keys %read_errors)) {
                    $log_text->Append("\tRead programmed data ($mem_type): FAILED\r\n");
                    print $to_errors "ERROR: Read data did not match data file at address " . sprintf("%#x", $_) . " of $mem_type.\r\n" . 
                        "    Data read was $read_errors{$_}.\r\n" foreach (keys %read_errors);
					$error_count += scalar keys %read_errors;
                } else {
                    $log_text->Append("\tRead programmed data ($mem_type): PASSED\r\n");
                }
            }
            
            #----- Device-Specific-Data Test -----#
            
			UNIQUE_DATA: foreach my $mem_type (keys %memory_types) {
				# Do a device-specific data test if there were any device-specific data files enabled in the XML.
				if (exists $data_files{$mem_type}{"Unique"}) {
					print $to_log_file FormatHeader("Read Device-specific Data"); 
					my @pcbs_to_test = ($unique_test_all) ? ( sort { $a <=> $b } keys %{$data_files{$mem_type}{"Unique"}} ) : ( $firstUniquePCB );
					foreach my $pcb_num (@pcbs_to_test) {
						my %read_errors = ();	
						my $read_totally_failed = 0;     
						my @banks = sort { $a <=> $b } keys %{$memory_types{$mem_type}};
						my @read_ranges = ();  # Will hold array references. Internal arrays will be [ range_start_addr, range_end_addr ].
					
						# Key is address, value is an array: [ data, bank ].
						# Will store all addresses and corresponding data in and around device-specific regions.
						my %good_data = ();  
						
						# Find the addresses present in each device-specific data file.
						foreach my $file (@{$data_files{$mem_type}{"Unique"}{$pcb_num}}) {
							# Find the address regions present in this file. $unique_regions[0] = start address; $unique_regions[1] = number of bytes in region.
							my @unique_regions = @{GetAddrsInFile($file)};
							foreach my $region_ref (@unique_regions) {
								# Read the data in this region from the file.
								my @data = @{ReadDataFile($file, $mem_type, $region_ref->[0], $region_ref->[1])};
								
								# For each address that has been read, identify which bank it is in and then store address, data, and bank in %good_data.
								foreach my $i (0 .. $region_ref->[1] - 1) {
									my $unique_bank = -1;
									foreach my $bank (@banks) {
										if (($region_ref->[0] + $i < $bank + $memory_types{$mem_type}{$bank}) && ($region_ref->[0] + $i >= $bank)) {
											$unique_bank = $bank;
											last;
										}
									}
									
									if ($unique_bank == -1) {
										print $to_errors "ERROR: Device-specific address " . $region_ref->[0] + $i . " does not exist in any bank. Device-specific-data test aborted.\r\n";
										$log_text->Append("\tRead device-specific data: FAILED\r\n");
										$error_count++;
										last UNIQUE_DATA;
									}
									
									$good_data{$region_ref->[0] + $i} = [ $data[$i], $unique_bank ];
								}
							}
						}
						
						# %good_data now contains all addresses and data in all device-specific files for the first PCB.
						my @unique_addrs = sort keys %good_data;
						
						# Loop through all unique addresses to define ranges to read from the part.
						foreach my $i (0 .. $#unique_addrs) {
							# Move on if this address is in the middle of a continuous range.
							# Only care about addresses which are not surrounded by other unique data.
							if (($i > 0) && ($i < $#unique_addrs)) {
								next if (($unique_addrs[$i] == ($unique_addrs[$i - 1] + 1)) && ($unique_addrs[$i] == ($unique_addrs[$i + 1] - 1)));
							}
							
							my $start_of_range = 0;
							my $end_of_range = 0;
							
							if ($i == 0) {
								$start_of_range = 1;
							} elsif ($unique_addrs[$i] != ($unique_addrs[$i - 1] + 1)) {
								$start_of_range = 1;
							}
							
							if ($i == $#unique_addrs) {
								$end_of_range = 1;
							} elsif ($unique_addrs[$i] != ($unique_addrs[$i + 1] - 1)) {
								$end_of_range = 1;
							}
							
							my $read_size = $read_size_max;
							
							# Find the relevant bank's index in the banks array.
							my $idx = first_index {$_ == $good_data{$unique_addrs[$i]}[1]} @banks;
							my $start_addr = undef;
							
							# First consider an address which is the start of a unique range.
							if ($start_of_range) {
								# If the current address is at the start of the bank, search for a previous bank to read.
								if ($unique_addrs[$i] == $banks[$idx]) {
									# If this is the very first address in the part, or this bank and the previous are not contiguous in memory, don't try to read addresses before this address.
									if (($idx == 0) || ($banks[$idx - 1] + $memory_types{$mem_type}{$banks[$idx - 1]} != $banks[$idx])) {
										$start_addr = $unique_addrs[$i];  # In this case, just start reading at the start of the unique range.
										$read_size = 0;
									} else {  # Otherwise, read from the previous bank as well.
										# Limit the read to the number of bytes in the previous bank if it is smaller than $read_size. 
										# Could go searching for more banks, but... this is good enough.
										$read_size = $memory_types{$mem_type}{$banks[$idx - 1]} if ($memory_types{$mem_type}{$banks[$idx - 1]} < $read_size);
										
											#				    bank				bank size
										$start_addr = $banks[$idx - 1] + $memory_types{$mem_type}{$banks[$idx - 1]} - $read_size;
									}
								} else {  # The address is the start of a range, but not the start of the bank.
									# If there are fewer than $read_size addresses in the bank before this address, only read what is there.
									$read_size = $unique_addrs[$i] - $banks[$idx] if (($unique_addrs[$i] - $banks[$idx]) < $read_size);
									$start_addr = $unique_addrs[$i] - $read_size;							
								}
								
								# Adjust $start_addr if it and other addresses in the range have already been covered.
								while (($read_size > 0) && (scalar @read_ranges != 0)) {
									if (($start_addr <= $read_ranges[-1][1])) {
										$read_size--;
										$start_addr++;
									} else {
										last;
									}
								}
								
								# Add a new anonymous array to the end of @read_ranges. I think that a start address should always be encountered before an end address,
								#   and that another start address won't be found before the end address of this range.
								# Don't add the new inner array if the end of the last range is directly before $start_addr. This will just be part of the same range
								#   and the end address of the inner array will be updated when the end of this unique range is found.
								push @read_ranges, [ $start_addr ] if ((scalar @read_ranges == 0) || ($read_ranges[-1][1] != $start_addr - 1));
								
							}
							
							if ($end_of_range) {  # This address is at the end of a unique range, scan addresses after it.
								# If the current address is at the end of a bank, search for a later bank to read.
								#                    bank start  +     bank size                          - 1 = bank end
								my $bank_end_addr = $banks[$idx] + $memory_types{$mem_type}{$banks[$idx]} - 1;
								if ($unique_addrs[$i] == $bank_end_addr) {
									# If this is the very last address in the part, or the next bank is not contiguous in memory, don't try to read addresses after this address.
									if (($idx == $#banks) || ($bank_end_addr != $banks[$idx + 1] - 1)) {
										$start_addr = $unique_addrs[$i] + 1;
										$read_size = 0;
									} else {  # Look for the end of the range in the next bank.									
										# Limit the read to the number of bytes in the next bank if it is smaller than $read_size_max.
										$read_size = $memory_types{$mem_type}{$banks[$idx + 1]} if ($memory_types{$mem_type}{$banks[$idx + 1]} < $read_size_max);
										$start_addr = $banks[$idx + 1];
									}
								} else {  # The address is the end of a range, but not the end of a bank.									
									$start_addr = $unique_addrs[$i] + 1;
									# Limit the read to the number of bytes remaining in the bank if it is smaller than $read_size_max.
									#             bank start  + bank size                              - this addr = read size
									$read_size = $banks[$idx] + $memory_types{$mem_type}{$banks[$idx]} - $start_addr if ($banks[$idx] + $memory_types{$mem_type}{$banks[$idx]} - $start_addr < $read_size_max);
								}
								
								# Check for a new unique range starting within $read_size bytes of $start_addr.
								# If there is one, end this range just before it.
								if ($read_size > 1) {
									foreach my $j (1 .. $read_size - 1) {
										if (exists $good_data{$start_addr + $j}) {
											$read_size = $j;
											last;
										}
									}
								}
								
								# Place the end of the region in the second element of the last array within @read_ranges.
								# The inner array should already contain the start address for this range.
								$read_ranges[-1][1] = $start_addr + $read_size - 1;
							}
						}
							
						# All ranges are now defined, next read good data from the files, and then read the part.
						foreach my $range_ref (@read_ranges) {
							print $to_log_file "----------\nRead PCB$pcb_num device-specific data at " . sprintf("0x%X-0x%X", $range_ref->[0], $range_ref->[1]) . "\n----------\n";
							
							# Loop through all commmon data files looking for the defined range.
							foreach my $file (@{$data_files{$mem_type}{"Common"}}) {
								my @data = @{ReadDataFile($file, $mem_type, $range_ref->[0], $range_ref->[1] - $range_ref->[0] + 1)};
								
								# Loop over all data read out and place it in %good_data if necessary.
								foreach my $j (0 .. $#data) {
									my $current_addr = $range_ref->[0] + $j;
									
									# Skip this address if it is in the unique areas; it has already been added to %good_data.
									next if (first { $_ == $current_addr } @unique_addrs);
									
									# If nothing yet recorded at this address, save either read data or blank data.
									if (not exists $good_data{$current_addr}) {
										if ($data[$j] eq "not found") {
											$good_data{$current_addr} = [ $blank_data{$mem_type} ];
										} else {
											$good_data{$current_addr} = [ $data[$j] ];
										}
									} elsif (($data[$j] ne "not found") && ($good_data{$current_addr}[0] eq $blank_data{$mem_type})) {
										# If valid data was found in this file, use it instead of the blank data that may have been assigned if 
										#   another file was checked first and nothing was found there.
										$good_data{$current_addr}[0] = $data[$j];
									}									
								}
							}
							
							# %good_data should now contain all addresses and corresponding data in the range,
							#   including the data from surrounding areas in common files (or blank data if there is no surrounding data).
							# Time to read it all out of the device and compare.
						
							# Make a string containing the range of addresses to read and the memory type to read from.
							# If alignment is 2, need to translate the hex file byte addresses into physical word addresses by dividing by 2.
							my $range = "";
							if ($alignment{$mem_type} == 1) {
								$range = sprintf("%#x-%#x %s", $range_ref->[0], $range_ref->[1], $mem_type); 
							} else {
								# The physical address will be the byte address divided by two, and only have 1 physical for every other byte.
								my @physical_addresses = map {$_ % 2 == 0 ? $_ / 2 : ()} ($range_ref->[0] .. $range_ref->[1]);
								$range = sprintf("%#x-%#x %s", $physical_addresses[0], $physical_addresses[-1], $mem_type);
							}
							
							my $pcb_mask = 1 << ($pcb_num - 1);
							$pcb_mask = sprintf("%#x", $pcb_mask);
							RunMISP("--read", $xml_out, $range . " -s " . $pcb_mask);  # Read the specified range, hopefully unique data and some surrounding it.
							print $to_log_file $misp_output;
							Cleanup() if $cancel_clicked;
							return 1 if $cancel_clicked;
							
							# Throw the data returned from all addresses into an array.
							my @data = $misp_output =~ m/Device Memory.*= 0x([0-9a-fA-F]*)/g;
							
							if (scalar @data == 0) {
								print $to_errors "ERROR: During device-specific-data test, no data was able to be read from addresses " . sprintf("0x%X-0x%X", $range_ref->[0], $range_ref->[1]) . ".\r\n";
								$read_totally_failed = 1;
								$error_count++;
							}
							
							# This array acts the same as @good_data in other read sections. I'm renaming it to avoid a bit of confusion with %good_data used in this section.
							# This is byte-addressed data as read from the data file.
							my @real_data = ();
							push @real_data, $good_data{$_}[0] foreach ($range_ref->[0] .. $range_ref->[1]);
							
							if ($alignment{$mem_type} == 2) {
								# If alignment is 2, shift data about to make word strings that will match the MISP output.
								if ($reverse_endian) {  # I'm assuming "reverse endian" is big endian. It's poorly named, but deal with it.
									my @index = map {$_ * 2} (0 .. ($#real_data - 1) / 2);  # Set up array with all even indices in the address array.
									@real_data = map {sprintf("0x%02x%02x", hex $real_data[$_], hex $real_data[$_ + 1])} @index;
								} else {  # Little endian.
									my @index = map {$_ * 2 + 1} (0 .. ($#real_data - 1) / 2);  # Set up array with all odd indices in the address array.
									@real_data = map {sprintf("0x%02x%02x", hex $real_data[$_], hex $real_data[$_ - 1])} @index;
								}
							}

							# If the alignment is 1 and the algorithm author was lazy, mask bytes as needed.
							if ($alignment{$mem_type} == 1 && $bytes_per_read > 1) {
								# Pick out the proper byte if there are multiple bytes reported for each address. Pad with leading 0's first.
								foreach my $i (0 .. $#data) {
									$data[$i] = sprintf("%0" . (2 * $bytes_per_read) . "x", hex $data[$i]) if (length $data[$i] < (2 * $bytes_per_read));
									my $offset = ($i % $bytes_per_read) * 2;
									$offset = ($bytes_per_read * 2) - $offset - 2 if $reverse_endian;
									$data[$i] = substr($data[$i], $offset, 2);
								}
							}
							
							# Check to make sure the array only contains correct data.
							foreach my $i (0 .. $#data) {
								$read_errors{$range_ref->[0] + $i} = $data[$i] if hex $data[$i] != hex $real_data[$i];
							}
						}
											
						# Display device-specific read errors if any occurred.
						if ($read_totally_failed) {
							$log_text->Append("\tRead device-specific data (PCB$pcb_num $mem_type): FAILED\r\n");
						} elsif (scalar (keys %read_errors)) {
							$log_text->Append("\tRead device-specific data (PCB$pcb_num $mem_type): FAILED\r\n");
							print $to_errors "ERROR: Device-specific-data test for PCB$pcb_num failed at address " . sprintf("%#x", $_) . ".\r\n" . 
								"    Data read was $read_errors{$_}.\r\n" foreach (keys %read_errors);
							$error_count += scalar keys %read_errors;
						} else {
							$log_text->Append("\tRead device-specific data (PCB$pcb_num $mem_type): PASSED\r\n");
						}
					}
				}
			}
        }
    }
    
    #-------------------#

    #---- Full test ----#

    #-------------------#
    
    if ($full_sequence eq $default_full_text) {
        print $to_errors "ERROR: No full sequence set up. This probably isn't a good choice.\r\n";
        $error_count++;
    } else {
		print $to_log_file FormatHeader("Full sequence");
		$log_text->Append("\r\nRunning full sequence...\r\n");
		
		for my $run (1 .. $full_num) {
			@test_result = RunMISP($full_sequence, $xml_out);
			Cleanup() if $cancel_clicked;
			return 1 if $cancel_clicked;
			print $to_log_file $misp_output;
			$log_text->Append("\tFull sequence trial $run: $test_result[0]");
			if ($test_result[0] ne "PASSED") {
				$log_text->Append("\r\n");
				print $to_errors "ERROR: Full sequence trial $run failed.\r\n";
				$error_count++;
			} elsif ($test_result[0] eq "PASSED") {
				$log_text->Append(" in $test_result[1] seconds\r\n");
			}
        }
		
		# Report any warnings from the misp output.
		my @warnings = $misp_output =~ m/Warning:\s*(.*)/g;
		@warnings = uniq(@warnings);
		if (scalar @warnings) {
			print $to_errors "\r\nMISP warnings:\r\n";
			print $to_errors "\t$_\r\n" foreach (@warnings);
		}
		
		# Even/Odd pcb test (if enabled)
		if ($even_odd) {
			$log_text->Append("\r\nRunning Evens/Odds tests...\r\n");
		
			# Generate even mask and run test
			my $pcb_mask = "";
			$pcb_mask = (($_ + 1) % 2) . $pcb_mask for (1 .. $numPCBs);
			$pcb_mask = sprintf("%#x", oct("0b$pcb_mask"));
			@test_result = RunMISP($full_sequence, $xml_out, "-s $pcb_mask");
			Cleanup() if $cancel_clicked;
			return 1 if $cancel_clicked;
			print $to_log_file FormatHeader("Even PCBs") . $misp_output;
			$log_text->Append("\tEven PCBs test: $test_result[0]\r\n");
			if ($test_result[0] eq "FAILED") {
				print $to_errors "ERROR: Even-PCBs-only test failed.\r\n";
				$error_count++;
			}
			
			# Generate odd mask and run test
			$pcb_mask = "";
			$pcb_mask = ($_ % 2) . $pcb_mask for (1 .. $numPCBs);
			$pcb_mask = sprintf("%#x", oct("0b$pcb_mask"));
			@test_result = RunMISP($full_sequence, $xml_out, "-s $pcb_mask");
			Cleanup() if $cancel_clicked;
			return 1 if $cancel_clicked;
			print $to_log_file FormatHeader("Odd PCBs") . $misp_output;
			$log_text->Append("\tOdd PCBs test: $test_result[0]\r\n");
			if ($test_result[0] eq "FAILED") {
				print $to_errors "ERROR: Odd-PCBs-only test failed.\r\n";
				$error_count++;
			}
		}
    }
	
	#----------------------#

    #- csMISPV3.ini Check -#

    #----------------------#
	
	my $ini_path = $datafile_dir . 'Bin\csMISPV3.ini';
	if (not -f $ini_path) {
        print $to_errors "ERROR: csMISPV3.ini not found.";
		$error_count++;
    } else {
		$log_text->Append("\r\nChecking files...\r\n");
		my $cfg = Config::IniFiles->new( -file => $ini_path );
		print $to_warnings "WARNING: csMISPV3.ini non-default value: fpgaClock = " . $cfg->val('system', 'fpgaClock') .
			". The default is 180.\r\n" if $cfg->val('system', 'fpgaClock') != 180;
		print $to_warnings "WARNING: csMISPV3.ini non-default value: fpgaClock2 = " . $cfg->val('system', 'fpgaClock2') .
			". The default is 240.\r\n" if $cfg->val('system', 'fpgaClock2') != 240;
		print $to_warnings "WARNING: csMISPV3.ini non-default value: initTimeout = " . $cfg->val('system', 'initTimeout') .
			". The default is 10000 ms.\r\n" if $cfg->val('system', 'initTimeout') ne "10000 ms";
		print $to_warnings "WARNING: csMISPV3.ini non-default value: cmdTimeout = " . $cfg->val('system', 'cmdTimeout') .
			". The default is 30000 ms.\r\n" if $cfg->val('system', 'cmdTimeout') ne "30000 ms";
		print $to_warnings "WARNING: csMISPV3.ini non-default value: globalTimeout = " . $cfg->val('system', 'globalTimeout') .
			". The default is 60s.\r\n" if $cfg->val('system', 'globalTimeout') ne "60s";
		print $to_warnings "WARNING: csMISPV3.ini non-default value: fpgaClock = " . $cfg->val('system', 'bufferSize') .
			". The default is 4096.\r\n" if $cfg->val('system', 'bufferSize') != 4096;
		print $to_warnings "WARNING: csMISPV3.ini contains more than one Section. Do you have an elf file enabled?\r\n" if ((scalar $cfg->Sections()) > 1);
			
		$log_text->Append("\tDefault csMISPV3.ini: " . (($warning_log =~ m/csMISPV3\.ini/) ? "WARNING" : "PASSED") . "\r\n");
	}
    
    #-------------------#

    #- Display Results -#

    #-------------------#
        
    $log_text->Append("\r\n" . $warning_log) if (length $warning_log != 0);
	$log_text->Append("\r\n" . $error_log . "\r\nSee $QA_dir$log_file for details.\r\n") if (length $error_log != 0);
    $log_text->Append("\r\nSUMMARY: There " . ($error_count == 1 ? "was" : "were") . 
        " $error_count error" . ($error_count == 1 ? "" : "s") . 
        "." . ($error_count == 0 ? " Ship it.\r\n" : "\r\n\r\n\r\n"));
    
    # Reset stuff before next run.
    Cleanup();
    return 1;
}

sub Cleanup {
    close $to_errors;
	close $to_warnings;
	close $to_log_file;
	CloseAllDataFiles();
}

sub FormatHeader {
	my $str = shift;
	my $len = length $str;
	my $border = "#" . "=" x ($len + 8) . "#\n";
	return "\n" . $border . "#--- $str ---#\n" . $border;
}

sub Main_Resize {
    my $mw = $main->ScaleWidth();
    my $mh = $main->ScaleHeight();
    # my $lw = $label->Width();
    # my $lh = $label->Height();    
    
    # $label->Left(($mw - $lw) / 2);
    
    # $label->Top(($mh - $lh) / 2);
    
    $run_button->Change(-top => $mh - $run_button->Height() - $body_margin,
                        -left => $mw - $run_button->Width() - $body_margin);  
                        
    # $log_file_field->Change(-top => $run_button->Top());
                        
    $browse_button->Change(-left => $mw - $browse_button->Width() - $body_margin,
                           -top => $xml_browser->Top());
    $xml_browser->Change(-height => 20,
                         -width => $mw - (2 * $body_margin) - $browse_button->Width() - 5);
    return 1;
    
}

sub Log_Resize {
    $log_text->Change(-height => $log_window->ScaleHeight() - 10 - $cancel_button->Height() - 10, #-height => $log_window->ScaleHeight() - 10,
                      -width => $log_window->ScaleWidth() - 10,
					  -left => 5);
					  
	$cancel_button->Change(-top => $log_text->Top() + $log_text->Height() + 10,
						   -left => $body_margin);
						   
	$close_button->Change(-top => $cancel_button->Top(),
						  -left => $log_window->ScaleWidth() - $close_button->Width() - $body_margin);
    return 1;
}

sub Main_DropFiles {
    my ($self, $dropObj) = @_;
    my $count = $dropObj->GetDroppedFiles();
    return if $count != 1;
    
    my $file = $dropObj->GetDroppedFile(0);
    
    $xml_browser->Change(-text => $file, -foreground => [0, 0, 0]);
    return 1;
}

sub Cancel_Click {
	$log_text->Append("\r\nOPERATION CANCELLED.\r\n");
	$cancel_clicked = 1;
	
	return 1;
}

sub Close_Results_Click {
	$log_window->Hide();
}

#####################

##### MISP subs #####

#####################

# Executes a MISP command.
# Arg1: $command - MISP command to be run (-k, -p, etc.).
# Arg2: $xml - Path to input XML file.
# Arg3: $options - Optional arguments associated with $command, such as an address to read.
# Returns: A list containing "PASSED" or "FAILED" at element 0 and the test time at element 1.
sub RunMISP {
    if (not -f $datafile_dir . "Bin\\csMISPV3.exe") {
        die $datafile_dir . "Bin\\csMISPV3.exe not found. How did you even manage to lose that?\n";
    }

    my $command = shift;
    my $xml = shift;
    my $options = shift // "";
    $misp_output = "";  # Reset output for new run.
    # @test_result = ();  # Reset test result for new run.
    
    if (not exists $commands{$command}) {
        if (not exists $missing_commands{$command}) {
            $missing_commands{$command} = 1;
            print $to_warnings "WARNING: No $command command in MISP setup. Related tests skipped. \r\n\r\n";
        }
        return "NO_COMMAND";
	} else {
        # Perform MISP step
		my $call_string = '"' . $datafile_dir . "Bin\\csMISPV3.exe\" -c $xml $command $options";
		
		my $misp_pid = open my $misp_pipe, '-|', $call_string or die "ERROR: Couldn't open pipe to csMISPV3.exe: $!";
		
		# Store the STDOUT from csMISPV3.exe in $misp_output. Break out and kill the process if Cancel button is clicked.
		while(<$misp_pipe>) {
			$misp_output .= $_;
			Win32::GUI::DoEvents();
			if ($cancel_clicked) {
				kill(9, $misp_pid);
				close($misp_pipe);
				return "CANCEL";
			}
		}
		
		close $misp_pipe;
        
        # Snag the pass/fail result and total test time.
        $misp_output =~ m/ISP Tests:\s*(PASSED|FAILED)\s\((\d*.\d*) Seconds/;
        if (not defined $1) {
            $error_count++;
            return "ERROR";
        }
		
		# Try to prevent false passes on operations that expect a failure.
		if ($misp_output =~ m/(?:No MultiWriter Boards could be found in the system|ISP Init failed)/) {
			$error_count++;
			return "ERROR";
		}

        return ($1, $2);
    }
}

#####################

### Data File subs ##

#####################

# The following block encloses all file-handling subs. It creates a "static" variable, %open_files,
# for use in all file-handling subs.
{
    # For %open_files, key is file name, value is reference to another hash
      # in which key is either "type" or "data". Values of "type" are "bin", "srec", or "hex".
      # Values of "data" are either a hex file object reference or a hash of binary data.
    my %open_files = ();
    
    # Open a data file. Currently supports Intel hex, srec, and binary formats
    # Arg1: $file - Input file name
    # Arg2: $mem_type - Memory type associated with this data file
    sub OpenDataFile {
        my $file = shift;
        my $mem_type = shift;
        
        # Set the working directory to the location of csMISPV3.exe so that 
        #   a relative path in the XML will work properly. I hope this works.
		#   Making relative paths absolute in the DataFiles twig handler.
        # chdir "C:\\CheckSum\\MISP\\Fixture USBDrive\\Bin\\";
        
        # Determine the type of the new file.
        my $extension = lc +(fileparse($file, @supported_types))[2];
		$open_files{$file}{"ext"} = substr $extension, 1;
        if ($extension eq ".hex") {
            $open_files{$file}{"type"} = "hex";
        } elsif ($extension eq ".s19" || $extension eq ".s28" || $extension eq ".s37" ||
                 $extension eq ".srec" || $extension eq ".srecord" || $extension eq ".mot" || $extension eq ".mhx") {
            $open_files{$file}{"type"} = "srec";
        } elsif ($extension eq ".bin") {
            $open_files{$file}{"type"} = "bin";
        }
        
        # Read the file into the data structure ($hex or %bin_hash).
        if ($open_files{$file}{"type"} eq "hex" || $open_files{$file}{"type"} eq "srec") {
            my $data_string = "";
            open my $data_file, '<', $file or die "Failed to open data file at \"$file\".\n";            
            
            # Read entire data file into $data_string. The "do" block is used to temporarily
            #   change $/ to undef so that the entire file will be read at once.
            $data_string = do { local $/; <$data_file> };
            
            # Create a Hex::Record object
            $open_files{$file}{"data"} = Hex::Record->new;
            $open_files{$file}{"type"} eq "hex" ? $open_files{$file}{"data"}->import_intel_hex($data_string) : 
                                                  $open_files{$file}{"data"}->import_srec_hex($data_string);
            
            close $data_file;
        } elsif ($open_files{$file}{"type"} eq "bin") {
            # Set an offset so that the addresses start at the starting address of the first bank.
            my $offset = min keys %{$memory_types{$mem_type}};
            
            open my $data_file, '<:raw', $file or die "Failed to open data file at \"$file\".\n";
            local $/ = \1;  # This sets the "line size" for reading the file
            
            while (<$data_file>) {
                # The innermost hash key is the numeric address, value is data at that address.
                # sprintf() is used to make a hex string, simply to match what will be returned
                #   by the hex record objects.
                $open_files{$file}{"data"}{$. + $offset} = sprintf("%x", unpack('C', $_));  
            }
            
            close $data_file;
        } else {
            $log_text->Append("ERROR: Format not recognized for data file: \"$file\".\r\n\r\n");
            $error_count++;
            return 1;
        }
        return 0;
    }
	
	# "Close" all opened data files. Essentially just purge the %open_files hash and start it anew.
	#     I don't know if this is the right way to do this. I'm a bit worried about memory leaks.
	sub CloseAllDataFiles {
		undef %open_files;
		%open_files = ();	
	}
    
    # Read from a data file. Currently supports Intel hex, srec, and binary formats
    # Arg1: $file - Input file name
    # Arg2: $mem_type - Memory type associated with this data file
    # Arg3: $addr - Starting address to read from
    # Arg4: $num_bytes - Number of bytes to read
    sub ReadDataFile {
        my $file = shift;
        my $mem_type = shift;
        my $addr = shift;
        my $num_bytes = shift; 
        my $data_ref = "";
        my $status = 0;
        
        # Set up new data file if the file has not yet been seen.
        $status = OpenDataFile($file, $mem_type) if not exists $open_files{$file};     
        
        # OpenDataFile() will return 1 if it fails to open the file. Cancel the read, if so.
        return "ERROR" if $status;
    
        # Read the desired address from the data structure
        if ($open_files{$file}{"type"} eq "hex" || $open_files{$file}{"type"} eq "srec") {
            $data_ref = $open_files{$file}{"data"}->get($addr, $num_bytes);            
        } elsif ($open_files{$file}{"type"} eq "bin") {
            my @temp_array = $open_files{$file}{"data"}{($addr .. $addr + $num_bytes - 1)};
            $data_ref = \@temp_array;
        }
        
        # Check if any element in the array is undefined, meaning that the address was 
        #   missing from the data file.
        foreach my $i (0 .. $#$data_ref) {
            # print $to_errors "WARNING: Some addresses in the $num_bytes bytes starting at $addr not found in data file: \"$file\".\n" if not defined $_;
			# The second part of this if checks if the address is already in the array.
            if (not defined $$data_ref[$i]) {
				push @missing_addr, $addr + $i if (not first {$_ eq $addr + $i} @missing_addr);
                $$data_ref[$i] = "not found";
            }
        }
		
		# if (scalar @missing_addr) {
			# print $to_errors "WARNING: " . scalar @missing_addr . " addresses not found in data file.\r\n";
			# print $to_errors sprintf("%X\r\n", $_) foreach (@missing_addr);
		# }
        
        return $data_ref;
    }
    
    # Change the data stored in %open_files and write the result to a new file.
    # Arg1: $file - File to modify.
    # Arg2: $mem_type - Memory type associated with this data file.
    # Arg3: $addr - Start address to write to.
    # Arg4: $data_ref - Reference to array of data to write.
    # Arg5: $restore - Optional flag to restore the stored data structure after writing to file (if 1).
    # Returns: 1 if the data file was not able to be opened, 0 otherwise. 
    sub WriteDataFile {
        my $file = shift;
        my $mem_type = shift;
        my $addr = shift;
        my $data_ref = shift;
        my $restore = shift // 1;
        
        # Set up new data file if the file has not yet been seen.
        my $status = OpenDataFile($file, $mem_type) if not exists $open_files{$file};
        
        # OpenDataFile() will return 1 if it fails to open the file. Cancel the write, if so.
        return 1 if $status;
        
        if ($open_files{$file}{"type"} eq "hex" || $open_files{$file}{"type"} eq "srec") {
            # Store current data if restoring after.
            my $current_data_ref = $open_files{$file}{"data"}->get($addr, scalar @$data_ref) if $restore;
            
            # Modify the hex record object.
            $open_files{$file}{"data"}->write($addr, $data_ref);
            
            # Write hex record object to a string of the proper type.
            my $data_string = ($open_files{$file}{"type"} eq "hex") ? $open_files{$file}{"data"}->as_intel_hex(0x10) :
                                                                      $open_files{$file}{"data"}->as_srec_hex(0x10);
            
            # Write the string to a file.
            my $path = $modified_data_file . "." . $open_files{$file}{"ext"};
            open my $out, '>', $path or die "Couldn't open output data file.";
            print $out $data_string;
            close $out;
            
            # Restore the hex record object if necessary.
            $open_files{$file}{"data"}->write($addr, $current_data_ref) if $restore;
            
        } elsif ($open_files{$file}{"type"} eq "bin") {
            # Store current data if restoring after.
            my @current_data = $open_files{$file}{"data"}{( $addr .. $addr + $#$data_ref )} if $restore;
            
            # Modify the bin hash.
            foreach my $i (0 .. $#$data_ref) {
                $open_files{$file}{"data"}{$i + $addr} = $$data_ref[$i];
            }
            
            # Write the hash to a file.
            my $path = $QA_dir . $modified_data_file . "." . $open_files{$file}{"type"};
            open my $out, '>:raw', $path or die "Couldn't open output data file.";
            local $\ = undef;
            print $out pack('C', hex $open_files{$file}{"data"}{$_}) foreach sort { $a <=> $b } keys %{$open_files{$file}{"data"}};
            close $out;
            
            # Restore the hash if necessary.
            if ($restore) {
                foreach my $i (0 .. $#$data_ref) {
                    $open_files{$file}{"data"}{$i + $addr} = $current_data[$i];
                }
            }
        }
        
        return 0;
    }
	
	# Check whether an address exists in a data file.
    # Arg1: $addr - Addresses to check for.
    # Arg2: $file - File in which to search.
	# Arg3: $mem_type - Memory type that file is associated with.
    # Returns: 1 if the address is present in the file, 0 if not, "ERROR" if the file couldn't be opened
	#			 or the file somehow didn't have a type associated with it (shouldn't happen). 
	sub IsAddrInFile {
		my ($addr, $file, $mem_type) = @_;
		
		# Set up new data file if the file has not yet been seen.
        my $status = OpenDataFile($file, $mem_type) if not exists $open_files{$file};
		
		# OpenDataFile() will return 1 if it fails to open the file. Cancel the write, if so.
        return "ERROR" if $status;
		
		if ($open_files{$file}{"type"} eq "hex" || $open_files{$file}{"type"} eq "srec") {
			return (defined $open_files{$file}{"data"}->get($addr, 1)->[0]) ? 1 : 0;
		} elsif ($open_files{$file}{"type"} eq "bin") {
			return (exists $open_files{$file}{"data"}{$addr}) ? 1 : 0;
		} else {
			return "ERROR";
		}
	}
	
	# Get an array of all addresses present in the data file. Each element of the array will be an array 
	#   reference corresponding to one contiguous memory region. The first element of this array is the 
	#   region start address and the second element is the number of bytes in the region.
	# Arg1: $file - File from which to get addresses.
	# Arg2: $mem_type - Memory type that file is associated with.
	# Returns: Array reference described above.
	sub GetAddrsInFile {
		my ($file, $mem_type) = @_;
		my $regions_ref = undef;
		
		# Set up new data file if the file has not yet been seen.
        my $status = OpenDataFile($file, $mem_type) if not exists $open_files{$file};
		
		# OpenDataFile() will return 1 if it fails to open the file. Cancel the write, if so.
        return "ERROR" if $status;
		
		if ($open_files{$file}{"type"} eq "hex" || $open_files{$file}{"type"} eq "srec") {
			$regions_ref = $open_files{$file}{"data"}->GetRegions();
		} else {
			return "ERROR";
		}
		
		return $regions_ref;
	}
        

    # EX - Reading from a hex file. Works for intel hex or srec
    # open my $fh, '<', "ASM_r1480_000.hex" or die "Couldn't open file";
    # my $string = do { local $/; <$fh> };
    # my $hex_record = Hex::Record->new;
    # $hex_record->import_intel_hex($string);
    # my $bytes_ref = $hex_record->get(0x1FC00000, 0x10);
    # close $fh;
    
    # EX - Modify bytes in a hex record object and then write it to a new file.
    # $hex_record->write($start_addr, ["AA", "BB", "CC"]);
    # $string = $hex_record->as_intel_hex(0x10);
    # open $fh, '>', "QA_hex.hex" or die "Couldn't open output file.";
    # print $fh $string;
    # close $fh;

    # EX - Reading from binary file
    # open my $fh, '<:raw', "test.bin" or die "Couldn't open file";
    # local $/ = \1;  # This sets the "line size" for reading the file    
    # while (<$fh>) {
        # print "Byte $. is $_ \n";
    # }
    # close $fh;
    
    # EX - Writing to binary file
    # open $fh, '>:raw', "test_out.bin" or die "Couldn't open output file.";
    # local $\ = undef;
    # print $fh pack('c', $hash{$_}) foreach sort { $a <=> $b } keys %hash;
    # close $fh;

    # EX - Get file name, extension, and path
    # my $path = 'D:\Work\5200-212.bmp';
    # my($filename, $dirs, $suffix) = fileparse($path, (".png", ".bmp"));
}

#####################

## XML Parser Subs ##

#####################

# Handler that will add all <Command> elements to %commands if auto-detecting from XML.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "Command"
sub AddCommand {
    if ($auto_detect) {
        my ( $twig, $elt ) = @_;
        my $com = $elt->first_child->text;
        # If it is a read command, simply store "--read", not the read options
        $com = "--read" if ((substr $com, 0, 6) eq "--read");
        $commands{$com} = $elt->first_child("Revision")->text;
    }
}

# Handler that will set the verbosity.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "verbosity"
sub SetVerbosity {
    my ( $twig, $elt ) = @_;
    $elt->set_text("4");
}

# Handler that will set up %blank_data with the blank data value for each memory type.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "blankdata"
sub BlankData {
    my ( $twig, $elt ) = @_;
    my $mem_type = $elt->parent()->att("Type");
    $blank_data{$mem_type} = $elt->text();
	$blank_data{$mem_type} =~ s/\s+//g;  # Remove any spaces that may foul up the data.
}

# Handler that will set up %memory_types with all existing memory types and banks.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "Bank"
sub AddBanks {
    my ($twig, $elt) = @_;
    my $addr = hex $elt->first_child("Addr")->text();
    my $size = hex $elt->first_child("Size")->text();
    $memory_types{$elt->parent()->parent()->att("Type")}{$addr} = $size;
}

# Handler that will set up %data_files with all existing data files.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "DataFile"
sub AddDataFiles {
    my ($twig, $elt) = @_;
    
    # Only grab enabled data files.
    if ($elt->first_child("Enable")->text() eq "Yes") {
		my $file = $elt->first_child("RecentFilePath")->text();
		
		# Give the file a full path if it has a relative path in the xml.
		if (substr($file, 0, 1) eq ".") {
			$file = $datafile_dir . substr($file, 2);
		} else {
			print $to_warnings "WARNING: Data file not referenced using relative path: $file.\r\n";
		}
		
		# If a common data file, add it to the array of common data files.
		$data_files{$elt->att("Memory_Type")}{"Common"} = [] if not exists $data_files{$elt->att("Memory_Type")}{"Common"};
		push @{$data_files{$elt->att("Memory_Type")}{"Common"}}, $file if ($elt->parent()->gi() eq "CommonData");
		# print "Added $file to list\n" if ($elt->parent()->gi() eq "CommonData");
		# print "@{$data_files{$elt->att(\"Memory_Type\")}{\"Common\"}}";
		
		# If a device-specific data file for an enabled device, add it to the unique hash (as value) along with its associated pcb number (as key).
		if (($elt->parent()->gi() eq "DeviceData") && ($elt->parent()->parent()->first_child("Enable")->text() eq "Yes")) {
			my $dev = $elt->parent()->parent();
			my $pcb = $dev->first_child("PCB")->text();
			push @{$data_files{$elt->att("Memory_Type")}{"Unique"}{$pcb}}, $file;
			$firstUniquePCB = $pcb if ((not defined $firstUniquePCB) || ($firstUniquePCB > $pcb));
		}
    }
    
    ### TO DO: Maybe add support for multiple common data files and device specific files. 
	###		   Done in this part, but implementation of device specific check in other parts of code is not complete.
}

# Handler that will set the log file to be output in the QA directory.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "logfile"
sub SetLogFile {
	my ($twig, $elt) = @_;
	$elt->set_text($QA_dir . $elt->text());
}

# Handler to track the highest MW port and PCB# in use, and therefore the number of MW cards.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "dev"
sub PortCount {
	my ($twig, $elt) = @_;
	$max_port = $elt->first_child("portconnection")->text() if $elt->first_child("portconnection")->text() > $max_port;
	$numPCBs = $elt->first_child("PCB")->text() if $elt->first_child("PCB")->text() > $numPCBs;
	
	# Also check if all devices are enabled. Throw a warning if not.
	print $to_warnings "WARNING: PCB\r\n" . $elt->first_child("PCB")->text() . " not enabled." if ($elt->first_child("Enable")->text() ne "Yes");
}

# Handler to set the alignment for each memory type.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "dev"
sub SetAlignment {
	my ($twig, $elt) = @_;
	$alignment{$elt->parent()->att("Type")} = $elt->text();
}