#
# Copyright 2015 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package apps::kayako::mode::liststatus;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::httplib;
use XML::XPath;
use Digest::SHA qw(hmac_sha256_base64);

my %handlers = (ALRM => {} );

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
         {
		"hostname:s"            => { name => 'hostname' },
		"port:s"                => { name => 'port' },
		"proto:s"               => { name => 'proto', default => "http" },
		"urlpath:s"             => { name => 'url_path', default => '/api/index.php?' },
		"kayako-api-key:s"		=> { name => 'kayako_api_key' },
		"kayako-secret-key:s"	=> { name => 'kayako_secret_key' },
         });
    $self->set_signal_handlers;
    return $self;
}

sub set_signal_handlers {
    my $self = shift;

    $SIG{ALRM} = \&class_handle_ALRM;
    $handlers{ALRM}->{$self} = sub { $self->handle_ALRM() };
}

sub class_handle_ALRM {
    foreach (keys %{$handlers{ALRM}}) {
        &{$handlers{ALRM}->{$_}}();
    }
}

sub handle_ALRM {
    my $self = shift;
    
    $self->{output}->output_add(severity => 'UNKNOWN',
                                short_msg => sprintf("Cannot finished scenario execution (timeout received)"));
    $self->{output}->display();
    $self->{output}->exit();
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (defined($self->{option_results}->{timeout}) && $self->{option_results}->{timeout} =~ /^\d+$/ &&
        $self->{option_results}->{timeout} > 0) {
        alarm($self->{option_results}->{timeout});
    }
    if (!defined($self->{option_results}->{'kayako_api_key'})) {
        $self->{output}->add_option_msg(short_msg => "Please specify an API key for Kayako.");
        $self->{output}->option_exit();
    }
    if (!defined($self->{option_results}->{'kayako_secret_key'})) {
        $self->{output}->add_option_msg(short_msg => "Please specify a secret key for Kayako.");
        $self->{output}->option_exit();
    }
}

sub run {
    my ($self, %options) = @_;
	my $salt;
	$salt .= int(rand(10)) for 1..10;
	my $digest = hmac_sha256_base64 ($salt, $self->{option_results}->{'kayako_secret_key'});
	$self->{option_results}->{'url_path'} .= "/Tickets/TicketStatus&apikey=" . $self->{option_results}->{'kayako_api_key'} . "&salt=" . $salt . "&signature=" . $digest . "=";	
	my $webcontent = centreon::plugins::httplib::connect($self);
	my $xp = XML::XPath->new( $webcontent );
	my $nodes = $xp->find('ticketstatuses/ticketstatus');

	foreach my $actionNode ($nodes->get_nodelist) {
		my ($id) = $xp->find('./id', $actionNode)->get_nodelist;
		my $trim_id = centreon::plugins::misc::trim($id->string_value);
		my ($title) = $xp->find('./title', $actionNode)->get_nodelist;
		my $trim_title = centreon::plugins::misc::trim($title->string_value);
        $self->{output}->output_add(long_msg => "'" . $trim_title . "' [id = " . $trim_id . "]");
    }

    $self->{output}->output_add(severity => 'OK',
                                short_msg => 'List status:');
    $self->{output}->display(nolabel => 1, force_ignore_perfdata => 1, force_long_output => 1);
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

List departmentf of kayako 

=over 8

=item B<--hostname>

IP Addr/FQDN of the webserver host (required)

=item B<--port>

Port used by Apache

=item B<--proto>

Specify https if needed

=item B<--proxyurl>

Proxy URL if any

=item B<--kayako-api-url>

This is the URL you should dispatch all GET, POST, PUT & DELETE requests to.

=item B<--kayako-api-key>

This is your unique API key.

=item B<--kayako-secret-key>

The secret key is used to sign all the requests dispatched to Kayako.

=back

=cut
