# --
# Kernel/System/CustomerUser/DB.pm - some customer user functions
# Copyright (C) 2002-2003 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: DB.pm,v 1.6.2.1 2003-02-08 13:29:02 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::System::CustomerUser::DB;

use strict;
use Kernel::System::CheckItem;

use vars qw(@ISA $VERSION);
$VERSION = '$Revision: 1.6.2.1 $';
$VERSION =~ s/^.*:\s(\d+\.\d+)\s.*$/$1/;

# --
sub new {
    my $Type = shift;
    my %Param = @_;

    # allocate new hash for object
    my $Self = {};
    bless ($Self, $Type);
    # --
    # check needed objects
    # --
    foreach (qw(DBObject ConfigObject LogObject PreferencesObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }
    # --
    # config options
    # --
    $Self->{CustomerTable} = $Self->{ConfigObject}->Get('CustomerUser')->{Params}->{Table} 
      || die "Need CustomerUser->Params->Table in Kernel/Config.pm!";
    $Self->{CustomerKey} = $Self->{ConfigObject}->Get('CustomerUser')->{CustomerKey} 
      || $Self->{ConfigObject}->Get('CustomerUser')->{Key} 
      || die "Need CustomerUser->CustomerKey in Kernel/Config.pm!";
    $Self->{CustomerID} = $Self->{ConfigObject}->Get('CustomerUser')->{CustomerID} 
      || die "Need CustomerUser->CustomerID in Kernel/Config.pm!";

    $Self->{CheckItemObject} = Kernel::System::CheckItem->new(%Param);
    
    return $Self;
}
# --
sub CustomerSearch {
    my $Self = shift;
    my %Param = @_;
    my %Users = ();
    # --
    # build SQL string
    # --
    $Param{UserLogin} =~ s/\*/%/g;
    my $SQL = "SELECT $Self->{CustomerKey} ";
    if ($Self->{ConfigObject}->Get('CustomerUser')->{CustomerUserListFileds}) {
        foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{CustomerUserListFileds}}) {
            $SQL .= ", $Entry";
        }
    }
    else {
        $SQL .= " , first_name, last_name, email ";
    }
    # --
    # get data
    # --
    $SQL .= " FROM " .
    " $Self->{CustomerTable} ".
    " WHERE " .
    " $Self->{CustomerKey} LIKE '$Param{UserLogin}' ";
    # add valid option
    if ($Self->{ConfigObject}->Get('CustomerUser')->{CustomerValid}) {
        $SQL .= "AND ".$Self->{ConfigObject}->Get('CustomerUser')->{CustomerValid}.
        " in ( ${\(join ', ', $Self->{DBObject}->GetValidIDs())} ) ";
    }
    $Self->{DBObject}->Prepare(SQL => $SQL);
    while (my @Row = $Self->{DBObject}->FetchrowArray()) {
         foreach (1..8) {
             if ($Row[$_]) {
                  $Users{$Row[0]} .= $Row[$_].' ';
             }
         }
         $Users{$Row[0]} =~ s/^(.*\s)(.+?\@.+?\..+?)(\s|)$/"$1" <$2>/;
    }
    return %Users;
}
# --
sub CustomerList {
    my $Self = shift;
    my %Param = @_;
    my $Valid = defined $Param{Valid} ? $Param{Valid} : 1;
    # --
    # build SQL string
    # --
    my $SQL = '';
    if ($Self->{ConfigObject}->Get('CustomerUser')->{CustomerListFileds}) {
        foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{CustomerListFileds}}) {
            $SQL .= " ,$Entry ";
        }
    }
    else {
        $SQL .= " , customer_id, comment";
    }
    # --
    # get data
    # --
    my %Users = $Self->{DBObject}->GetTableData(
        What => "$Self->{CustomerID} $SQL ",
        Table => $Self->{CustomerTable}, 
        Clamp => 1,
        Valid => $Valid,
    ); 
    return %Users;
}
# --
sub CustomerUserList {
    my $Self = shift;
    my %Param = @_;
    my $Valid = defined $Param{Valid} ? $Param{Valid} : 1;
    # --
    # get data
    # --
    my %Users = $Self->{DBObject}->GetTableData(
        What => "$Self->{CustomerKey}, login, customer_id ",
        Table => $Self->{CustomerTable}, 
        Clamp => 1,
        Valid => $Valid,
    ); 
    return %Users;
}
# --
sub CustomerUserDataGet {
    my $Self = shift;
    my %Param = @_;
    my %Data;
    # --
    # check needed stuff
    # --
    if (!$Param{User} && !$Param{CustomerID}) {
        $Self->{LogObject}->Log(Priority => 'error', Message => "Need User or CustomerID!");
        return;
    }
    # --
    # build select
    # --
    my $SQL = "SELECT ";
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
        $SQL .= " $Entry->[2], ";
    }
    $SQL .= $Self->{CustomerKey}." FROM $Self->{CustomerTable} WHERE ";
    if ($Param{User}) {
        $SQL .= $Self->{CustomerKey}." = '$Param{User}'";
    }
    elsif ($Param{CustomerID}) {
        $SQL .= $Self->{CustomerID}." = '$Param{CustomerID}'";
    }
    # --
    # get inital data
    # --
    $Self->{DBObject}->Prepare(SQL => $SQL);
    while (my @Row = $Self->{DBObject}->FetchrowArray()) {
        my $MapCounter = 0;
        foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
            $Data{$Entry->[0]} = $Row[$MapCounter];
            $MapCounter++;
        }
    }
    # --
    # check data
    # --
    if (! exists $Data{UserLogin} && $Param{User}) {
        $Self->{LogObject}->Log(
          Priority => 'notice',
          Message => "Panic! No UserData for customer user: '$Param{User}'!!!",
        );
        return;
    }
    if (! exists $Data{UserLogin} && $Param{CustomerID}) {
#        $Self->{LogObject}->Log(
#          Priority => 'notice',
#          Message => "Panic! No UserData for customer id: '$Param{CustomerID}'!!!",
#        );
        return;
    }
    # compat!
    $Data{UserID} = $Data{UserLogin};
    # --
    # get preferences
    # --
    my %Preferences = $Self->{PreferencesObject}->GetPreferences(UserID => $Data{UserID});

    # return data
    return (%Data, %Preferences);
}
# --
sub CustomerUserAdd {
    my $Self = shift;
    my %Param = @_;
    # --
    # check needed stuff
    # --
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
      if (!$Param{$Entry->[0]} && $Entry->[4]) {
        $Self->{LogObject}->Log(Priority => 'error', Message => "Need $Entry->[0]!");
        return;
      }
    }
    if (!$Param{UserID}) {
        $Self->{LogObject}->Log(Priority => 'error', Message => "Need UserID!");
        return;
    }
    # --
    # check email address
    # --
    if ($Param{UserEmail} && !$Self->{CheckItemObject}->CkeckEmail(Address => $Param{UserEmail})) {
        $Self->{LogObject}->Log(
            Priority => 'error', 
            Message => "Email address ($Param{UserEmail}) not valid (".
              $Self->{CheckItemObject}->CheckError().")!",
        );
        return;
    }
    # --
    # quote params
    # -- 
    $Param{UserPassword} = crypt($Param{UserPassword}, $Param{UserLogin});
    foreach (keys %Param) {
       $Param{$_} = $Self->{DBObject}->Quote($Param{$_}) || '';
    }
    # --
    # build insert
    # --
    my $SQL = "INSERT INTO $Self->{CustomerTable} (";
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
        $SQL .= " $Entry->[2], ";
    }
    $SQL .= "create_time, create_by, change_time, change_by)";
    $SQL .= " VALUES (";
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
        if ($Entry->[5] =~ /^int$/i) {
            $SQL .= " $Param{$Entry->[0]}, ";
        }
        else {
            $SQL .= " '$Param{$Entry->[0]}', ";
        }
    }
    $SQL .= "current_timestamp, $Param{UserID}, current_timestamp, $Param{UserID})";
    if ($Self->{DBObject}->Do(SQL => $SQL)) {
      # --
      # log notice
      # --
      $Self->{LogObject}->Log(
          Priority => 'notice',
          Message => "CustomerUser: '$Param{UserLogin}' created successfully ($Param{UserID})!",
      );
      return $Param{UserLogin}; 
    }
    else {
        return;
    }
}
# --
sub CustomerUserUpdate {
    my $Self = shift;
    my %Param = @_;
    # --
    # check needed stuff
    # --
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
      if (!$Param{$Entry->[0]} && $Entry->[4]) {
        $Self->{LogObject}->Log(Priority => 'error', Message => "Need $Entry->[0]!");
        return;
      }
    }
    # --
    # check email address
    # --
    if ($Param{UserEmail} && !$Self->{CheckItemObject}->CkeckEmail(Address => $Param{UserEmail})) {
        $Self->{LogObject}->Log(
            Priority => 'error', 
            Message => "Email address ($Param{UserEmail}) not valid (".
                $Self->{CheckItemObject}->CheckError().")!",
        );
        return;
    }
    # --
    # get old user data (pw)
    # --
    my %UserData = $Self->CustomerUserDataGet(User => $Param{ID});
    # --
    # quote params
    # -- 
    foreach (keys %Param) {
        $Param{$_} = $Self->{DBObject}->Quote($Param{$_}) || '';
    }
    # -- 
    # update db
    # --
    my $SQL = "UPDATE $Self->{CustomerTable} SET ";
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
        if ($Entry->[5] =~ /^int$/i) {
            $SQL .= " $Entry->[2] = $Param{$Entry->[0]}, ";
        }
        elsif ($Entry->[0] !~ /^UserPassword$/i) {
            $SQL .= " $Entry->[2] = '$Param{$Entry->[0]}', ";
        }
    }
    $SQL .= " change_time = current_timestamp, ";
    $SQL .= " change_by = $Param{UserID} ";
    $SQL .= " WHERE ".$Self->{CustomerKey}." = '$Param{ID}'";
  
    if ($Self->{DBObject}->Do(SQL => $SQL)) {
        # --
        # log notice
        # --
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message => "CustomerUser: '$Param{UserLogin}' updated successfully ($Param{UserID})!",
        );
        # --
        # check pw
        # --
        my $GetPw = $UserData{UserPassword} || '';
        if ($GetPw ne $Param{UserPassword}) {
            $Self->SetPassword(UserLogin => $Param{UserLogin}, PW => $Param{UserPassword});
        }
        return 1;
    }
    else {
        return; 
    }
}   
# --
sub SetPassword {
    my $Self = shift;
    my %Param = @_;
    my $Pw = $Param{PW} || '';
    # --
    # check needed stuff
    # --
    if (!$Param{UserLogin}) {
        $Self->{LogObject}->Log(Priority => 'error', Message => "Need UserLogin!");
        return;
    }
    # --
    # crypt pw
    # --    
    my $NewPw = $Self->{DBObject}->Quote(crypt($Pw, $Param{UserLogin}));
    # --
    # update db
    # --
    foreach my $Entry (@{$Self->{ConfigObject}->Get('CustomerUser')->{Map}}) {
        if ($Entry->[0] =~ /^UserPassword$/i) {
            $Param{PasswordCol} = $Entry->[2];
        }
        if ($Entry->[0] =~ /^UserLogin$/i) {
            $Param{LoginCol} = $Entry->[2];
        }
    }
    if ($Self->{DBObject}->Do(
            SQL => "UPDATE $Self->{CustomerTable} ".
               " SET ".
               " $Param{PasswordCol} = '$NewPw' ".
               " WHERE ".
               " $Param{LoginCol} = '$Param{UserLogin}'",
    )) {
        # --
        # log notice
        # --
        $Self->{LogObject}->Log(
          Priority => 'notice',
          Message => "CustomerUser: '$Param{UserLogin}' changed password successfully!",
        );
        return 1;
    }
    else {
        return;
    }
}
# --
sub GetGroups {
    return;
}
# --
sub GenerateRandomPassword {
    my $Self = shift;
    my %Param = @_;
    # Generated passwords are eight characters long by default.
    my $Size = $Param{Size} || 8;

    # The list of characters that can appear in a randomly generated password.
    # Note that users can put any character into a password they choose themselves.
    my @PwChars = (0..9, 'A'..'Z', 'a'..'z', '-', '_', '!', '@', '#', '$', '%', '^', '&', '*');

    # The number of characters in the list.
    my $PwCharsLen = scalar(@PwChars);

    # Generate the password.
    my $Password = '';
    for ( my $i=0 ; $i<$Size ; $i++ ) {
        $Password .= $PwChars[rand($PwCharsLen)];
    }

    # Return the password.
    return $Password;
}
# --

1;
