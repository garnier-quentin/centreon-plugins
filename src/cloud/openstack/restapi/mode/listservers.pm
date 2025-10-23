#
# Copyright 2025 Centreon (http://www.centreon.com/)
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

package cloud::openstack::restapi::mode::listservers;

use base qw(centreon::plugins::mode);

use strict;
use warnings;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $options{options}->add_options(arguments => {});

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
}

my @mapping = ('projectName', 'id', 'serverName', 'vmState', 'powerState');

sub manage_selection {
    my ($self, %options) = @_;

    my $map_power_state = {
        0 => 'noState', 
        1 => 'running', 
        3 => 'paused', 
        4 => 'shutdown', 
        6 => 'crashed', 
        7 => 'suspended'
    };
    my $results = {};

    my $projects = $options{custom}->get_projects();
    foreach my $project (@$projects) {
        my $servers = $options{custom}->get_servers(project_id => $project->{id});
        
        foreach my $server (@$servers) {
            $results->{ $project->{id} . $server->{id} } = {
                serverName => $server->{name},
                id => $server->{id},
                projectName => $project->{name},
                vmState => lc($server->{'OS-EXT-STS:vm_state'}),
                powerState => $map_power_state->{ $server->{'OS-EXT-STS:power_state'} }
            };
        }
    }

    return $results;
}

sub run {
    my ($self, %options) = @_;

    my $results = $self->manage_selection(custom => $options{custom});
    foreach my $instance (sort keys %$results) {
        $self->{output}->output_add(long_msg => 
            join('', map("[$_: " . $results->{$instance}->{$_} . ']', @mapping))
        );
    }

    $self->{output}->output_add(
        severity => 'OK',
        short_msg => 'List servers:'
    );
    $self->{output}->display(nolabel => 1, force_ignore_perfdata => 1, force_long_output => 1);
    $self->{output}->exit();
}

sub disco_format {
    my ($self, %options) = @_;

    $self->{output}->add_disco_format(elements => \@mapping);
}

sub disco_show {
    my ($self, %options) = @_;

    my $results = $self->manage_selection(custom => $options{custom});
    foreach (sort keys %$results) {        
        $self->{output}->add_disco_entry(
            %{$results->{$_}}
        );
    }
}
1;

__END__

=head1 MODE

List servers.

=over 8

=back

=cut
