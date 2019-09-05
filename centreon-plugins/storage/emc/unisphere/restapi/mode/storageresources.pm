#
# Copyright 2019 Centreon (http://www.centreon.com/)
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

package storage::emc::unisphere::restapi::mode::storageresources;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use storage::emc::unisphere::restapi::mode::components::resources qw($health_status);
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold catalog_status_calc);

sub custom_status_output {
    my ($self, %options) = @_;

    my $msg = 'status : ' . $self->{result_values}->{status};
    return $msg;
}

sub custom_usage_output {
    my ($self, %options) = @_;
    
    my ($total_size_value, $total_size_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{total_space_absolute});
    my ($total_used_value, $total_used_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{used_space_absolute});
    my ($total_free_value, $total_free_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{free_space_absolute});
    my $msg = sprintf('space usage total: %s used: %s (%.2f%%) free: %s (%.2f%%)',
        $total_size_value . " " . $total_size_unit,
        $total_used_value . " " . $total_used_unit, $self->{result_values}->{prct_used_space_absolute},
        $total_free_value . " " . $total_free_unit, $self->{result_values}->{prct_free_space_absolute}
    );
    return $msg;
}

sub custom_allocated_output {
    my ($self, %options) = @_;
    
    my ($total_size_value, $total_size_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{total_space_absolute});
    my ($total_used_value, $total_used_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{used_alloc_absolute});
    $self->{result_values}->{free_alloc_absolute} = 0 if ($self->{result_values}->{free_alloc_absolute} < 0);
    $self->{result_values}->{prct_free_alloc_absolute} = 0 if ($self->{result_values}->{prct_free_alloc_absolute} < 0);
    my ($total_free_value, $total_free_unit) = $self->{perfdata}->change_bytes(value => $self->{result_values}->{free_alloc_absolute});
    my $msg = sprintf('allocated usage total: %s used: %s (%.2f%%) free: %s (%.2f%%)',
           $total_size_value . " " . $total_size_unit,
           $total_used_value . " " . $total_used_unit, $self->{result_values}->{prct_used_alloc_absolute},
           $total_free_value . " " . $total_free_unit, $self->{result_values}->{prct_free_alloc_absolute}
    );
    return $msg;
}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'sr', type => 1, cb_prefix_output => 'prefix_sr_output', message_multiple => 'All storage resources are ok' },
    ];
    
    $self->{maps_counters}->{sr} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'status' }, { name => 'display' } ],
                closure_custom_calc => \&catalog_status_calc,
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold,
            }
        },
        { label => 'usage', nlabel => 'storageresource.space.usage.bytes', set => {
                key_values => [ { name => 'used_space' }, { name => 'free_space' }, { name => 'prct_used_space' }, { name => 'prct_free_space' }, { name => 'total_space' }, { name => 'display' },  ],
                closure_custom_output => $self->can('custom_usage_output'),
                perfdatas => [
                    { value => 'used_space_absolute', template => '%d', min => 0, max => 'total_space_absolute',
                      unit => 'B', cast_int => 1, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'usage-free', nlabel => 'storageresource.space.free.bytes', display_ok => 0, set => {
                key_values => [ { name => 'used_space' }, { name => 'free_space' }, { name => 'prct_used_space' }, { name => 'prct_free_space' }, { name => 'total_space' }, { name => 'display' },  ],
                closure_custom_output => $self->can('custom_usage_output'),
                perfdatas => [
                    { value => 'free_space_absolute', template => '%d', min => 0, max => 'total_space_absolute',
                      unit => 'B', cast_int => 1, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'usage-prct', nlabel => 'storageresource.space.usage.percentage', display_ok => 0, set => {
                key_values => [ { name => 'prct_used_space' }, { name => 'display' } ],
                output_template => 'used : %.2f %%',
                perfdatas => [
                    { value => 'prct_used_space_absolute', template => '%.2f', min => 0, max => 100,
                      unit => '%', label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'allocated', nlabel => 'storageresource.allocated.usage.bytes', display_ok => 0, set => {
                key_values => [ { name => 'used_alloc' }, { name => 'free_alloc' }, { name => 'prct_used_alloc' }, { name => 'prct_free_alloc' }, { name => 'total_space' }, { name => 'display' },  ],
                closure_custom_output => $self->can('custom_allocated_output'),
                perfdatas => [
                    { value => 'used_alloc_absolute', template => '%d', min => 0, max => 'total_space_absolute',
                      unit => 'B', cast_int => 1, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'allocated-prct', display_ok => 0, nlabel => 'storageresource.allocated.usage.percentage', set => {
                key_values => [ { name => 'prct_used_alloc' }, { name => 'display' } ],
                output_template => 'allocated used : %.2f %%',
                perfdatas => [
                    { value => 'prct_used_alloc_absolute', template => '%.2f', min => 0, max => 100,
                      unit => '%', label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, force_new_perfdata => 1);
    bless $self, $class;
    
    $options{options}->add_options(arguments => { 
        'filter-name:s'     => { name => 'filter_name' },
        'unknown-status:s'  => { name => 'unknown_status', default => '%{status} =~ /unknown/i' },
        'warning-status:s'  => { name => 'warning_status', default => '%{status} =~ /ok_but|degraded|minor/i' },
        'critical-status:s' => { name => 'critical_status', default => '%{status} =~ /major|criticalnon_recoverable/i' },
    });
    
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $self->change_macros(macros => ['warning_status', 'critical_status', 'unknown_status']);
}

sub prefix_sr_output {
    my ($self, %options) = @_;
    
    return "Storage resource '" . $options{instance_value}->{display} . "' ";
}

sub manage_selection {
    my ($self, %options) = @_;

    my $results = $options{custom}->request_api(url_path => '/api/types/storageResource/instances');

    $self->{sr} = {};
    foreach (@{$results->{entries}}) {
        if (defined($self->{option_results}->{filter_name}) && $self->{option_results}->{filter_name} ne '' &&
            $_->{content}->{name} !~ /$self->{option_results}->{filter_name}/) {
            $self->{output}->output_add(long_msg => "skipping storage resource '" . $_->{content}->{name} . "': no matching filter.", debug => 1);
            next;
        }

        $self->{sr}->{$_->{content}->{id}} = {
            display => $_->{content}->{name},
            status => $health_status->{ $_->{content}->{health}->{value} },
            total_space => $_->{content}->{sizeTotal},
            used_space => $_->{content}->{sizeUsed},
            free_space => $_->{content}->{sizeTotal} - $_->{content}->{sizeUsed},
            prct_used_space => $_->{content}->{sizeUsed} * 100 / $_->{content}->{sizeTotal},
            prct_free_space => 100 - ($_->{content}->{sizeUsed} * 100 / $_->{content}->{sizeTotal}),

            used_alloc => $_->{content}->{sizeAllocated},
            free_alloc => $_->{content}->{sizeTotal} - $_->{content}->{sizeAllocated},
            prct_used_alloc => $_->{content}->{sizeAllocated} * 100 / $_->{content}->{sizeTotal},
            prct_free_alloc => 100 - ($_->{content}->{sizeAllocated} * 100 / $_->{content}->{sizeTotal}),
        };
    }
    
    if (scalar(keys %{$self->{sr}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No storage resource found");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check storage resources.

=over 8

=item B<--filter-counters>

Only display some counters (regexp can be used).
Example: --filter-counters='^usage$'

=item B<--filter-name>

Filter name (can be a regexp).

=item B<--unknown-status>

Set warning threshold for status (Default: '%{status} =~ /unknown/i').
Can used special variables like: %{status}, %{display}

=item B<--warning-status>

Set warning threshold for status (Default: '%{status} =~ /ok_but|degraded|minor/i').
Can used special variables like: %{status}, %{display}

=item B<--critical-status>

Set critical threshold for status (Default: '%{status} =~ /major|criticalnon_recoverable/i').
Can used special variables like: %{status}, %{display}

=item B<--warning-*> B<--critical-*>

Thresholds.
Can be: 'usage' (B), 'usage-free' (B), 'usage-prct' (%),
'allocated', 'allocated-prct'.

=back

=cut
