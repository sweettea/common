##
# Perl interface to Jira defect tracking system
#
# @synopsis
#
#     use Permabit::Jira;
#     $jira = Permabit::Jira->new();
#     $jira->getProjectLeadName(<project-name>);
#     $jira->createIssue(project   => <project-name>,
#                        component => <component-name>,
#                        assignee  => <jira-account-name>);
#
# @description
#
# C<Permabit::Jira> provides an object oriented interface to the
# Permabit defect tracking system (Jira).  It can be used to create issues,
# and many other interactions can be implemented using the Jira REST API.
#
# $Id$
##
package Permabit::Jira;

use strict;
use warnings FATAL => qw(all);
use Carp qw(cluck);
use HTTP::Request;
use JSON qw(encode_json decode_json);
use Log::Log4perl;
use LWP::UserAgent;
use Permabit::Assertions qw(assertMinArgs assertMinMaxArgs assertNumArgs);
use Permabit::Configured;

use base qw(Permabit::Configured);

my  $log  = Log::Log4perl->get_logger(__PACKAGE__);

######################################################################
# @inherit
##
sub initialize {
  my ($self) = assertNumArgs(1, @_);

  $self->{restVersion} //= "latest";

  # Avoid spurious 500 errors when running locally by telling perl not
  # to check that the cert matches the hostname.
  $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

  # Create an LWP UserAgent for http operations.
  $self->{_userAgent} = LWP::UserAgent->new();
  $self->{_userAgent}->ssl_opts(verify_hostname => 0);
  $self->{_userAgent}->ssl_opts(SSL_verify_mode => 0x00);
}

######################################################################
# Issue a request to the Jira server and get a response.
#
# @param  method   The request method (GET, POST, etc.)
# @param  command  The Jira resource and command to send
# @oparam content  The content of the request
#
# @return  the decoded result of the request
##
sub sendRequest {
  my ($self, $method, $command, $content)
    = assertMinMaxArgs([ undef ], 3, 4, @_);

  if (defined($content)) {
    $content = encode_json($content);
  }

  my $uri = join('/', $self->{server}, "rest", "api", $self->{restVersion});
  my $request = HTTP::Request->new($method, "$uri/$command",
                                   [ Content_Type => 'application/json', ],
                                   $content);
  $request->authorization_basic($self->{username}, $self->{password});

  my $response = $self->{_userAgent}->request($request);

  if ($response->is_success()) {
    if ($response->content_type() eq 'application/json') {
      return decode_json($response->decoded_content());
    } else {
      return $response->decoded_content();
    }
  }

  # Verbose logging makes it easier to see what the server didn't like.
  my $errorMessage = $response->status_line();
  if ($response->decoded_content()) {
    if ($response->content_type() eq 'application/json') {
      my $jsonContent = decode_json($response->decoded_content());
      $errorMessage .= '\n'. Data::Dumper->Dump([ $jsonContent ]);
    } else {
      $errorMessage .= '\n'. $response->decoded_content();
    }
  }

  $errorMessage .= "\nin response to request:\n";
  if ($request->decoded_content()) {
    if ($request->content_type() eq 'application/json') {
      my $jsonContent = decode_json($request->decoded_content());
      $errorMessage .= Data::Dumper->Dump([ $jsonContent ]);
    } else {
      $errorMessage .= $request->decoded_content();
    }
  }

  cluck("Error running command: $method $uri: $errorMessage");
  return undef;
}

######################################################################
# Create an issue
#
# @param params{project}      The Jira project name
# @param params{component}    The component of the project
# @param params{summary}      The text title of the issue
# @param params{description}  A more verbose description of the issue
# @param params{reporter}     The Jira username reporting the issue
# @param params{assignee}     The Jira username to whom to assign the issue
# @param params{priority}     The priority of the issue (e.g. 'Major')
# @param params{version}      The version in which the issue is found, which
#                               is also the initial fix in version
#
# @return  the Jira issue key
##
sub createIssue {
  my ($self, %params) = assertMinArgs(1, @_);
  $params{priority} ||= 'Normal';

  # Set basic content fields
  my $content = {
                 fields => {
                            project     => { key => $params{project} },
                            priority    => { name => $params{priority} },
                            issuetype   => { name => 'Bug' },
                            summary     => $params{summary},
                            description => $params{description},
                           },
                };

  # Add fields that need specific handling when they are not provided
  if (defined($params{assignee})) {
    $content->{fields}{assignee} = { name => $params{assignee} };
  }

  if (defined($params{reporter})) {
    $content->{fields}{reporter} = { name => $params{reporter} };
  }

  if (defined($params{component})) {
    $content->{fields}{components} = [ { name => $params{component} } ];
  }

  if (defined($params{version})) {
    $content->{fields}{versions}    = [ { name => $params{version} } ];
    $content->{fields}{fixVersions} = [ { name => $params{version} } ];
  }

  my $newIssue = $self->sendRequest('POST', "issue", $content);
  return (defined($newIssue) ? $newIssue->{'key'} : undef);
}

######################################################################
# Get the username of a project's lead.
#
# @param project  The Jira project name (e.g., QA)
#
# @return  the user name of the project lead
##
sub getProjectLeadName {
  my ($self, $project) = assertNumArgs(2, @_);
  if (!defined($project)) {
    cluck("No project provided");
    return undef;
  }

  my $response = $self->sendRequest('GET', "project/$project");
  return (defined($response) ? $response->{lead}->{name} : undef);
}

1;
