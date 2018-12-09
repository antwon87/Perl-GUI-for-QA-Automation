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
                            
my $xml_browser = $main->AddTextfield(-name => 'BrowseField',
									  -text => 'Drop or Select MISP XML file',
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
                                    -tip => 'Commands present in the exported MISP step will be used for the QA.',
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
                                      
my $run_button = $main->AddButton(-name => 'Run',
                                  -text => 'QA it now',
                                  -font => $run_font,
                                  -width => 150,
                                  -height => 60);   

my $log_text = $log_window->AddTextfield(-name => 'LogText', -readonly => 1, -text => "blue");        

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
                                           -directory => 'G:\Anthony\\');
    $xml_browser->Change(-text => $text, -foreground => [0, 0, 0]) if defined $text;
    return 1;
}

sub BrowseField_GotFocus {
    # When the field gets focus, clear the default text if it is there.
    # Also set the text to black instead of the default gray.
	if ($xml_browser->Text() eq 'Select MISP XML file') {
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
		$xml_browser->Change(-text => 'Select MISP XML file',
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
    }
    return 1;
}

sub Run_Click {
    # Do the thing
    $log_window->Resize($w, $h);
    $log_window->Move($main->Left() + 20, $main->Top() + 20);
    $log_text->Change(-text => "foo",
                      -height => $log_window->ScaleHeight() - 10,
                      -width => $log_window->ScaleWidth() - 10,
                      -top => 5,
                      -left => 5);
    $log_window->Show();
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