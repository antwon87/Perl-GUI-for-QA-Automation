use strict;
use warnings;

use 5.010;
use XML::Twig;
use File::Basename;
use File::Path qw( make_path );
use List::Util qw ( min );
use List::MoreUtils qw( minmax );
use Hex::Record;
use Cwd qw( getcwd );
use Win32::GUI();
use Win32::GUI::DropFiles;

#####################

### MISP Variables ##

#####################

my @supported_types = ( ".bin", ".hex", ".s19", ".s29", ".s37", ".srec", ".srecord" );
my %commands = ();
my %missing_commands = ();
my $misp_output = "";
my %memory_types = ();
my $error_count = 0;
my $QA_dir = 'C:\CheckSum\MW_QA\\';
my $modified_data_file = $QA_dir . "QA_data";
my $log = "";  # This string will contain all log data to be displayed in the GUI.
my %blank_data = ();
my %data_files = ();  # $data_files{$mem_type}
my $auto_detect = 0;
my $bytes_per_read = 1;
    
# Create a "file handle" to the log string. This will allow me to print to the string.
# I'll open this in the Run Button event section.
# open my $to_log, '>', \$log or die "Can't open \$to_log: $!\n";
my $to_log;

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

my $small_icon = new Win32::GUI::Icon('checkmark_new_small.ico');
my $big_icon = new Win32::GUI::Icon('checkmark_new.ico');
$main->SetIcon($small_icon, 0);
$main->SetIcon($big_icon, 1);

my $log_window = Win32::GUI::Window->new(-name => 'Log',
                                         -parent => $main,
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
									  -text => 'C:\CheckSum\misp1.txt',##$default_browse_text,
									  -height => 20,
									  -width => 250,
									  -left => $body_margin,
                                      -top => $input_label->Top() + $input_label->Height() + $body_above,
                                      -foreground => [150, 150, 150]);
                                      
my $browse_button = $main->AddButton(-name => 'BrowseButton',
                              -text => 'Browse',
                              -top => $xml_browser->Top(),
							  -left => $xml_browser->Left() + $xml_browser->Width() + 5);
                            
my $read_label = $main->AddLabel(-text => 'Read Configuration',
							-top => $xml_browser->Top() + $xml_browser->Height() + $header_above,
                            -left => $header_margin,
                            -font => $heading);
                            
my $read_bytes = $main->AddTextfield(-name => 'Bytes',
                                     -height => 20,
                                     -width => 40,
                                     -top => $read_label->Top() + $read_label->Height() + $body_above,
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
                                 -disabled => 1);

my $commands_label = $main->AddLabel(-text => 'Supported Commands',
							-top => $read_bytes->Top() + $read_bytes->Height() + $header_above,
                            -left => $header_margin,
                            -font => $heading);

my $auto_check = $main->AddCheckbox(-name => 'AutoCheck',
                                    -text => 'Auto-detect from XML',
                                    -tip => "Commands present in the exported MISP step will be used for the QA.",
                                    -top => $commands_label->Top() + $commands_label->Height() + $body_above,
                                    -left => $body_margin);
                                     
my $program_check = $main->AddCheckbox(-text => '-p',
                                       -top => $auto_check->Top() + $auto_check->Height() + $body_above,
                                       -left => $auto_check->Left());
                                    
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
                                    -left => $blank_check->Left());
                                    
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
                                         -text => "blue",
                                         -multiline => 1,
                                         -vscroll => 1);

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

# close $to_log;

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
    my %addresses = ();  # $addresses{$mem_type}{top/bot}[addresses], stores addresses used for read/verify
    my %read_once = ();
    $auto_detect = $auto_check->Checked();
    my $reverse_endian = $endian->Checked();
    $bytes_per_read = $read_bytes->Text(); 
    my $full_sequence = $full_text->Text();
    
    # Open the "file handle" for printing to the log string.
    open $to_log, '>', \$log or die "Can't open \$to_log: $!\n";
    
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
    # die "ERROR: You must set a full programming sequence.\n" if $full_sequence eq $default_full_text;

    # Create a directory for the QA files if it doesn't already exist.
    make_path $QA_dir if not -d $QA_dir;

    #### TO DO: Delete all files generated by this script prior to running anew. ####

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
                                                 Memory => \&MemoryTypes,
                                                 Bank => \&AddBanks,
                                                 DataFile => \&AddDataFiles} );

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

    # If there is a read command, set up read addresses for top and bottom of part.
    if (not exists $commands{"--read"}) {
        if (not exists $missing_commands{"--read"}) {
            $missing_commands{"--read"} = 1;
            print $to_log "WARNING: No --read command in MISP setup. Related tests skipped. \r\n\r\n";
        }
    } else {
        foreach my $mem_type (keys %memory_types) {
            # Find the bank with the lowest and the bank with the highest addresses
            my ($min_bank, $max_bank) = minmax keys %{$memory_types{$mem_type}};

            my $read_size = $read_size_max;
            my $size = $memory_types{$mem_type}{$min_bank};

            # If a bank is smaller than the default number of bytes to read, only read as many
            #   bytes as there are. If that small bank is the only bank, don't bother reading it twice.
            if ($read_size <= $size) {
                $read_size = $size;
                $read_once{$mem_type} = 1 if $min_bank == $max_bank;
            }
            
            # Set up hash containing addresses to read at the top of the memory type.
            $addresses{$mem_type}{"top"} = [$min_bank .. $min_bank + $read_size - 1];

            # Don't read the bottom of the memory if the top covered the whole thing. Unlikely... but let's check anyway.
            next if ($read_once{$mem_type});

            # Reset variables
            $read_size = $read_size_max;
            $size = $memory_types{$mem_type}{$max_bank};
            $read_size = $size if ($read_size < $size);
            
            # Set up hash containing addresses to read at the bottom of the memory type.
            $addresses{$mem_type}{"bottom"} = [$max_bank + $size - $read_size .. $max_bank + $size - 1];
        }
    }

    # If there is a verify command, set up a middle address to modify.
    if (not exists $commands{"-v"}) {
        if (not exists $missing_commands{"-v"}) {
            $missing_commands{"-v"} = 1;
            print $to_log "WARNING: No -v command in MISP setup. Related tests skipped. \r\n\r\n";
        }
    } else {
        foreach my $mem_type (keys %memory_types) {
            # Skip this memory type if there is no associated data file.
            next if $data_files{$mem_type} eq "";
            
            # Find the middle of the total size.
            my $total_size = 0;
            $total_size += $memory_types{$mem_type}{$_} foreach keys %{$memory_types{$mem_type}};
            my $mid = int ($total_size / 2);
            
            # Iterate through banks to find what address will be the middle.
            my $count = 0;
            foreach my $bank (keys %{$memory_types{$mem_type}}) {
                $count += $memory_types{$mem_type}{$bank};  # Add bank size to $count.
                if ($count >= $mid) {  # This bank contains the middle address.
                    # I think this will be the middle address...
                    # Start of bank + bank size = max bank address
                    # Count - mid = how far before the max bank address the mid is
                    # Max bank address - (count - mid) = middle address!
                    # - 1 at the end because count and mid are 1-indexed, memory is not
                    $addresses{$mem_type}{"mid"}[0] = $bank + $memory_types{$mem_type}{$bank} - ($count - $mid) - 1;
                    last;
                }
            }
        }
    }

    #-------------------#

    #---- ID Tests  ----#

    #-------------------#

    if (not exists $commands{"-k"}) {
        $missing_commands{"-k"} = 1;
        print $to_log "WARNING: No -k command in MISP setup. ID check skipped. Does this chip have an ID? \r\n\r\n";
    } else {
        # First test uses base XML file, presumably with the correct device ID
        # $twig->print_to_file($xml_out, PrettyPrint => "indented" );

        @test_result = RunMISP("-k", $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Device ID test failed with given ID. See log for details.\r\n\r\n";
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
        if ($test_result[0] eq "PASSED") {
            print $to_log "ERROR: Device ID test passed with altered ID. See log for details.\r\n\r\n";
            $error_count++;
        }
    }

    #-------------------#

    #--- Erase Tests ---#

    #-------------------#

    if (not exists $commands{"--chiperase"} && not exists $commands{"-e"}) {
        $missing_commands{"--chiperase"} = 1;
        $missing_commands{"-e"} = 1;
        print $to_log "WARNING: No chip erase command in MISP setup. Blank tests skipped. Can this chip be erased? \r\n\r\n";
    } else {
        # Erase the chip
        my $erase_command = (exists $commands{"--chiperase"} ? "--chiperase" : "-e");
        @test_result = RunMISP($erase_command, $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Chip erase failed. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # Do a blank check
        @test_result = RunMISP("-b", $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Blank check failed. Chip not blank after erase. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # Do a verify
        @test_result = RunMISP("-v", $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Verify succeeded after erase. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # Do read tests, unless there is no --read command in the setup.
        if (exists $commands{"--read"}) {
            foreach my $mem_type (keys %memory_types) {
                my %read_errors = ();
                
                # Make a string containing the range of addresses to read and the memory type to read from
                my $range = sprintf("%#x-%#x %s", $addresses{$mem_type}{"top"}[0], $addresses{$mem_type}{"top"}[-1], $mem_type); 
                RunMISP("--read", $xml_out, $range);  # Read from the top of the memory
                
                # Throw the data returned from all addresses into an array.
                my @data = $misp_output =~ m/Device Memory.*=\s(.*)/g;

                # Check to make sure the array only contains correct data.
                foreach my $i (0 .. $#data) {
                    $read_errors{$addresses{$mem_type}{"top"}[$i]} = $data[$i] if $data[$i] != $blank_data{$mem_type};
                }
                
                # Skip bottom read if it was covered by the top read.
                next if exists $read_once{$mem_type};
                
                # Set up the address range for the bottom of the memory.
                $range = sprintf("%#x-%#x %s", $addresses{$mem_type}{"bottom"}[0], $addresses{$mem_type}{"bottom"}[-1], $mem_type);
                RunMISP("--read", $xml_out, $range);  # Read the bottom of the bank.    

                # Throw the data returned from all addresses into an array.
                @data = $misp_output =~ m/Device Memory.*=\s(.*)/g;

                # Check to make sure the array only contains blank data.
                foreach my $i (0 .. $#data) {
                    $read_errors{$addresses{$mem_type}{"bottom"}[$i]} = $data[$i] if hex $data[$i] == hex $blank_data{$mem_type};
                }
                
                # Display read errors if any occurred.
                if (scalar (keys %read_errors)) {
                    print $to_log "ERROR: Blank data read failed at address " . sprintf("%#x", $_) . " of $mem_type.\r\n" . 
                    "    Data read was $read_errors{$_}.\n" foreach (keys %read_errors);
                    print $to_log "\r\n";
                }
            }
        }
        
    }

    #-------------------#

    #-- Program Tests --#

    #-------------------#

    if (not exists $commands{"-p"}) {
        $missing_commands{"-p"} = 1;
        print $to_log "WARNING: No -p command in MISP setup. Programming tests skipped. Can this chip be programmed? \r\n\r\n";
    } else {
        # Program the chip
        @test_result = RunMISP("-p", $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Programming failed. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # Program it again to make sure you can program a pre-programmed chip
        @test_result = RunMISP("-p", $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Programming failed when the chip is already programmed. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # Do a blank check
        @test_result = RunMISP("-b", $xml_out);
        if ($test_result[0] eq "PASSED") {
            print $to_log "ERROR: Blank check passed. Chip blank after programming. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # Do a verify
        @test_result = RunMISP("-v", $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Verify failed after programming. See log for details.\r\n\r\n";
            $error_count++;
        }
        
        # If the verify command exists, modify bytes in the data file to verify verify.
        if (not exists $missing_commands{"-v"}) {
        
            foreach my $mem_type (keys %memory_types) {
                # Skip this memory type if there is no associated data file.
                next if $data_files{$mem_type} eq "";
                    
                # Find the current data file field in the XML.
                my $elt = $root->next_elt("DataFile");
                while ($elt->att("Memory_Type") ne $mem_type && defined $elt) {
                    $elt->next_elt("DataFile");
                }
                
                # Skip this memory type if an associated data file is not found. This shouldn't
                #   ever happen because the previous "next" should catch it. But just in case.
                next if not defined $elt;
                
                # Change XML to use the modified data file.
                my $extension = lc +(fileparse($data_files{$mem_type}, @supported_types))[2];
                my $new_path = $modified_data_file . $extension;
                $elt->first_child("RecentFilePath")->set_text($new_path);
                $twig->print_to_file($xml_verify, PrettyPrint => "indented" );
                
                # Modify a byte at each of the top, middle, and bottom.
                foreach (keys %{$addresses{$mem_type}}) {
                    # Read the current byte.
                    my $temp_data = ReadDataFile($data_files{$mem_type}, $mem_type, $addresses{$mem_type}{$_}[0], 1);
                    
                    # Increment said byte and store it as a string again.
                    $$temp_data[0] = hex $$temp_data[0] == 255 ? 0 : (hex $$temp_data[0]) + 1;
                    $$temp_data[0] = sprintf("%x", $$temp_data[0]);
                    
                    # Write modified byte to new file. The data structure in memory will be restored to the previous
                    #   state after writing out the modified file.
                    WriteDataFile($data_files{$mem_type}, $mem_type, $addresses{$mem_type}{$_}[0], $temp_data);
                    
                    # Verify with the modified file, expecting a failure.
                    @test_result = RunMISP("-v", $xml_verify);
                    if ($test_result[0] eq "PASSED") {
                        print $to_log "ERROR: Verify passed after modifying address $addresses{$mem_type}{$_}[0] in the data file.\r\n\r\n";
                        $error_count++;
                    }
                }
                
                # Restore the XML file to the original data file.
                $elt->first_child("RecentFilePath")->set_text($data_files{$mem_type});
            }
        }
        
        # Write config words if a -w command exists in the XML
        if (exists $commands{"-w"}) {
            @test_result = RunMISP("-w", $xml_out);
            if ($test_result[0] eq "FAILED") {
                print $to_log "ERROR: Config word write failed. See log for details.\r\n\r\n";
                $error_count++;
            }
        }
        
        # Do read top/bottom tests, unless there is no --read command in the setup.
        if (exists $commands{"--read"}) {
            foreach my $mem_type (keys %memory_types) {
                # Skip this memory type if there is no associated data file.
                next if $data_files{$mem_type} eq "";
            
                my %read_errors = ();
                
                # Make a string containing the range of addresses to read and the memory type to read from
                my $range = sprintf("%#x-%#x %s", $addresses{$mem_type}{"top"}[0], $addresses{$mem_type}{"top"}[-1], $mem_type); 
                RunMISP("--read", $xml_out, $range);  # Read from the top of the memory
                
                # Throw the data returned from all addresses into an array.
                my @data = $misp_output =~ m/Device Memory.*=\s(.*)/g;
                
                # Read the addresses from the data file. Arguments are the data file, the starting address, and the length of the address array.
                my @good_data = ReadDataFile($data_files{$mem_type}, $mem_type, $addresses{$mem_type}{"top"}[0], scalar @{$addresses{$mem_type}{"top"}});
                
                next if $good_data[0] eq "ERROR";            
                
                # Check to make sure the array only contains correct data.
                foreach my $i (0 .. $#data) {
                    # Skip the good data comparison if the address was not found in the data file
                    if (not defined $good_data[$i]) {
                        $read_errors{$addresses{$mem_type}{"top"}[$i]} = $data[$i];
                    } else {                
                        $read_errors{$addresses{$mem_type}{"top"}[$i]} = $data[$i] if $data[$i] != $good_data[$i];
                    }
                }
                
                # Skip bottom read if it was covered by the top read.
                next if exists $read_once{$mem_type};
                
                # Set up the address range for the bottom of the memory.
                $range = sprintf("%#x-%#x %s", $addresses{$mem_type}{"bottom"}[0], $addresses{$mem_type}{"bottom"}[-1], $mem_type);
                RunMISP("--read", $xml_out, $range);  # Read the bottom of the bank.    

                # Throw the data returned from all addresses into an array.
                @data = $misp_output =~ m/Device Memory.*= 0x([0-9a-fA-F]*)/g;
                
                foreach my $i (0 .. $#data) {
                    my $offset = ($i % $bytes_per_read) * 2;
                    $offset = ($bytes_per_read * 2) - $offset - 2 if $reverse_endian;
                    $data[$i] = substr($data[$i], $offset, 2);
                }

                # Check to make sure the array only contains correct data.
                foreach my $i (0 .. $#data) {
                    # Skip the good data comparison if the address was not found in the data file
                    if (not defined $good_data[$i]) {
                        $read_errors{$addresses{$mem_type}{"top"}[$i]} = $data[$i];
                    } else {                
                        $read_errors{$addresses{$mem_type}{"top"}[$i]} = $data[$i] if hex $data[$i] == hex $good_data[$i];
                    }
                }
                
                # Display read errors if any occurred.
                if (scalar (keys %read_errors)) {
                    print $to_log "ERROR: Read data did not match data file at address " . sprintf("%#x", $_) . " of $mem_type.\n" . 
                        "    Data read was $read_errors{$_}.\n" foreach (keys %read_errors);
                    print $to_log "\r\n";
                }
            }
        }
        
        ### TO DO: Maybe try to add a check for unique data.
        
    }
    
    #-------------------#

    #---- Full test ----#

    #-------------------#
    
    if ($full_sequence eq $default_full_text) {
        print $to_log "ERROR: No full sequence set up. This probably isn't a good choice.\r\n\r\n";
        $error_count++;
    } else {
        @test_result = RunMISP($full_sequence, $xml_out);
        if ($test_result[0] eq "FAILED") {
            print $to_log "ERROR: Full sequence failed. See log for details.\r\n\r\n";
            $error_count++;
        } elsif ($test_result[0] eq "PASSED") {
            print $to_log "Full programming sequence passed in $test_result[1] seconds.\r\n\r\n";
        }
        ### TO DO: Get an output log with warnings in it to see the format. Report any warnings here.
        # if ($misp_output =~ m/WARNING: 
    }
    
    ### TO DO: Make full sequence run multiple times.

    
    #-------------------#

    #- Display Results -#

    #-------------------#
    
    print $to_log "SUMMARY: There " . ($error_count == 1 ? "was" : "were") . 
        " $error_count error" . ($error_count == 1 ? "" : "s") . 
        "." . ($error_count == 0 ? " Ship it.\r\n" : "\r\n");    
    
    # Set the log window text to the new log string.
    # If the window is hidden, show it in the default location.
    $log_text->Change(-text => $log);
    if (not $log_window->IsVisible()) {
        $log_window->Resize($w, $h);
        $log_window->Move($main->Left() + 20, $main->Top() + 20);
        $log_text->Change(-height => $log_window->ScaleHeight() - 10,
                          -width => $log_window->ScaleWidth() - 10,
                          -top => 5,
                          -left => 5);
        $log_window->Show();
    }
    
    # Reset stuff before next run.
    $error_count = 0;
    %missing_commands = ();
    %memory_types = ();
    %blank_data = ();
    %data_files = ();
    %commands = ();
    close $to_log;
    $log = "";
   
    return 1;
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
    $log_text->Change(-height => $log_window->ScaleHeight() - 10,
                      -width => $log_window->ScaleWidth() - 10);
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

#####################

##### MISP subs #####

#####################

# Executes a MISP command.
# Arg1: $command - MISP command to be run (-k, -p, etc.).
# Arg2: $xml - Path to input XML file.
# Arg3: $options - Optional arguments associated with $command, such as an address to read.
# Returns: A list containing "PASSED" or "FAILED" at element 0 and the test time at element 1.
sub RunMISP {
    if (not -f "C:\\CheckSum\\MISP\\Fixture USBDrive\\Bin\\csMISPV3.exe") {
        die "C:\\CheckSum\\MISP\\Fixture USBDrive\\Bin\\csMISPV3.exe not found. How did you even manage to lose that?\n";
    }

    my $command = shift;
    my $xml = shift;
    my $options = shift // "";
    $misp_output = "";  # Reset output for new run.
    # @test_result = ();  # Reset test result for new run.
    
    if (not exists $commands{$command}) {
        if (not exists $missing_commands{$command}) {
            $missing_commands{$command} = 1;
            print $to_log "WARNING: No $command command in MISP setup. Related tests skipped. \r\n\r\n";
        }
        return "NO_COMMAND";
    } else {
        # Perform MISP step
		# print $to_log "Running: C:\\CheckSum\\MISP\\\"Fixture USBDrive\"\\Bin\\csMISPV3.exe -c $xml $command $options\r\n";
        $misp_output = `\"C:\\CheckSum\\MISP\\Fixture USBDrive\\Bin\\csMISPV3.exe\" -c $xml $command $options`;
		# print $to_log "MISP output: \r\n $misp_output\r\n\r\n";
        
        # Snag the pass/fail result and total test time.
        $misp_output =~ m/ISP Tests:\s*(PASSED|FAILED)\s\((\d*.\d*) Seconds/;
        if (not defined $1) {
            print $to_log "ERROR: $command test incomplete, no pass or fail recorded. See log for details.\r\n\r\n";
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
        chdir "C:\\CheckSum\\MISP\\Fixture USBDrive\\Bin\\";
        
        # Determine the type of the new file.
        my $extension = lc +(fileparse($file, @supported_types))[2];
        if ($extension eq ".hex") {
            $open_files{$file}{"type"} = "hex";
        } elsif ($extension eq ".s19" || $extension eq ".s28" || $extension eq ".s37" ||
                 $extension eq ".srec" || $extension eq ".srecord") {
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
            print $to_log "ERROR: Format not recognized for data file: \"$file\".\r\n\r\n";
            $error_count++;
            return 1;
        }
        return 0;
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
            $open_files{$file}{"data"}->get($addr, $num_bytes);            
        } elsif ($open_files{$file}{"type"} eq "bin") {
            my @temp_array = $open_files{$file}{"data"}{($addr .. $addr + $num_bytes - 1)};
            $data_ref = \@temp_array;
        }
        
        # Check if any element in the array is undefined, meaning that the address was 
        #   missing from the data file.
        foreach my $i (0 .. $#$data_ref) {
            # print $to_log "WARNING: Some addresses in the $num_bytes bytes starting at $addr not found in data file: \"$file\".\n" if not defined $_;
            if (not defined $$data_ref[$i]) {
                print $to_log "WARNING: Address " . sprintf("%#x", $addr + $i) . " not found in data file: \"$file\".\r\n\r\n";
                $$data_ref[$i] = "not found";
            }
            
        }
        
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
            my $path = $QA_dir . $modified_data_file . "." . $open_files{$file}{"type"};
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
    
    # Adjust the blank data to have the same number of bytes as are output when reading an address.
    # $len_dif is the length difference in characters.
                # 2 chars per byte + 2 for 0x
    my $len_dif = ($bytes_per_read * 2 + 2) - (length $blank_data{$mem_type});
    if ($len_dif > 0) {
        # Append first blank data digit until length matches
        $blank_data{$mem_type} .= substr($blank_data{$mem_type}, 2, 1) x $len_dif;
    } elsif ($len_dif < 0) {
        # Crop off the end of the blank data string
        $blank_data{$mem_type} = substr($blank_data{$mem_type}, 0, (length $blank_data{$mem_type}) + $len_dif);
    }
}

# Handler that will set up %memory_types with all existing memory types.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "Memory"
sub MemoryTypes {
    my ($twig, $elt ) = @_;
    $memory_types{$elt->att("Type")} = {};
    # The anonymous hash will be filled with bank addresses and sizes by the SetBanks function
}

# Handler that will set up %memory_types with all existing memory banks.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "Bank"
sub AddBanks {
    my ($twig, $elt) = @_;
    my $addr = hex $elt->first_child("Addr")->text();
    my $size = hex $elt->first_child("Size")->text();
    $memory_types{$elt->parent()->parent()->att("Type")}{$addr} = hex $size;
}

# Handler that will set up %data_files with all existing data files.
# Arg1: $twig - reference to twig object
# Arg2: $elt - reference to twig element with name of "DataFile"
sub AddDataFiles {
    my ($twig, $elt) = @_;
    
    # Only grab common data files.
    if ($elt->parent()->gi() eq "CommonData") {
        $data_files{$elt->att("Memory_Type")} = $elt->first_child("RecentFilePath")->text();
    }
    
    ### TO DO: Maybe add support for multiple common data files and device specific files. ###
}