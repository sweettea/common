package EnabledPath;

use Permabit::Assertions qw(assertNumArgs);

use base qw(Permabit::Configured);

########################################################################
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  $self->{initialized} = 1;
}

########################################################################
##
sub foo {
  my ($self) = assertNumArgs(1, @_);

  return "baz:$self->{foo}"
}

1;

