##
# Test the LabUtils module
#
# $Id$
##
package testcases::LabUtils_t1;

use strict;
use warnings FATAL => qw(all);
use English qw(-no_match_vars);
use Permabit::Assertions qw(
  assertEqualNumeric
  assertFalse
  assertNe
  assertNumArgs
  assertTrue
);
use Permabit::AsyncSub;
use Permabit::LabUtils qw(_machineClass isVirtualMachine);
use Permabit::RSVP;
use Permabit::SystemUtils qw(runCommand);

use base qw(Permabit::Testcase);

my $log = Log::Log4perl->get_logger(__PACKAGE__);

# The classes shouldn't care about shorted names vs FQDNs, which is
# good, because for Beaker machines we'll be getting FQDNs.
my %machineClasses = (
    'machine-1'             => 'LabMachine',
    'machine-2.example.com' => 'LabMachine',
    );

########################################################################
##
sub set_up {
  $ENV{PERMABIT_PERL_CONFIG} =  Class::Inspector->filename(__PACKAGE__);
  $ENV{PERMABIT_PERL_CONFIG} =~ s/pm$/yaml/;
}

######################################################################
##
sub testMachineClasses {
  my ($self) = @_;
  my @hosts = keys(%machineClasses);
  my $failCount = 0;
  foreach my $hostname (@hosts) {
    my $expectedClass = $machineClasses{$hostname};
    my $gotClass = _machineClass($hostname);
    if ($gotClass ne $expectedClass) {
      $log->error("host '$hostname' got class '$gotClass',"
                  . " expected '$expectedClass'");
      $failCount++;
    }
  }
  assertEqualNumeric(0, $failCount);
}

######################################################################
##
sub _testOneVirtual {
  my ($self, $hostname) = @_;
  my $isVirtual = isVirtualMachine($hostname);
  if (($hostname =~ /banana-jr-6000/) || ($hostname =~ /iFruit-3000/)) {
    assertTrue($isVirtual);
  } else {
    # With the artificial machines excluded, all else are expected to
    # have systemd-detect-virt.
    my $detected = runCommand($hostname, "systemd-detect-virt");
    chomp($detected->{stdout});
    assertNe("", $detected->{stdout},
             "systemd-detect-virt output shouldn't be empty");
    if ($detected->{stdout} eq "none") {
      assertFalse($isVirtual);
    } else {
      assertEqualNumeric(0, $detected->{status},
                         "systemd-detect-virt detected virtualization");
      assertTrue($isVirtual,
                 "isVirtualMachine should return true for $detected->{stdout}");
    }
  }
  return "$hostname: $isVirtual";
}

######################################################################
##
sub testVirtual {
  my ($self) = @_;
  # Start with some non-existent (and thus unreachable by ssh) names, assumed
  # to be Permabit lab machines and thus processed by name-based heuristics.
  my @hosts = (
               'banana-jr-6000',
               'banana-jr-6000.example.com',
               'iFruit-3000',
               'iFruit-3000.example.com',
              );
  # Test any hosts that are currently free in RSVP.
  my $rsvp = Permabit::RSVP->new();
  my @rsvpHosts = @{$rsvp->listHosts()};
  my @freeHostNames = map { $_->[0] } grep { !defined($_->[1]) } @rsvpHosts;
  push(@hosts, @freeHostNames);
  # Test each one, in parallel.
  my @subs;
  foreach my $host (@hosts) {
    my $sub = Permabit::AsyncSub->new(code => sub {
                                        $self->_testOneVirtual($host);
                                      });
    $sub->start();
    push(@subs, $sub);
  }
  # Collect all results.
  my $failedCount = 0;
  foreach my $sub (@subs) {
    $sub->wait();
    if ($sub->status() eq "ok") {
      $log->info($sub->result());
    } else {
      $failedCount++;
      $log->error($sub->error());
    }
  }
  assertEqualNumeric(0, $failedCount);
}

1;
