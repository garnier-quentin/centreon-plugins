#
# Copyright 2026-Present Centreon (http://www.centreon.com/)
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

package apps::monitoring::zscaler::zdx::api::custom::graphql;

use strict;
use warnings;
use centreon::plugins::http;
use centreon::plugins::statefile;
use centreon::plugins::misc qw(json_encode json_decode is_empty value_of is_excluded);
use centreon::plugins::constants qw(:messages);
use Digest::SHA qw(sha256_hex);
use DateTime;

sub new {
    my ($class, %options) = @_;
    my $self  = {};
    bless $self, $class;

    if (!defined($options{output})) {
        print "Class Custom: Need to specify 'output' argument.\n";
        exit 3;
    }
    $options{output}->option_exit(short_msg => "Class Custom: Need to specify 'options' argument.")
        unless $options{options};
    
    if (!defined($options{noptions})) {
        $options{options}->add_options(arguments => {
            'auth-url:s'       => { name => 'auth_url', default => '' },
            'client-id:s'      => { name => 'client_id', default => '' },
            'client-secret:s'  => { name => 'client_secret', default => '' },
            'api-path:s'       => { name => 'api_path', default => '/zins/graphql' },
            'hostname:s'       => { name => 'hostname', default => 'api.zsapi.net' },
            'port:s'           => { name => 'port', default => 443 },
            'proto:s'          => { name => 'proto', default => 'https' },
            'timeout:s'        => { name => 'timeout', default => 10 },
            'cache-lifetime:s' => { name => 'cache_lifetime', default => 1800 }
        });
    }
    $options{options}->add_help(package => __PACKAGE__, sections => 'ANALYTICS API OPTIONS', once => 1);

    $self->{output} = $options{output};
    $self->{http} = centreon::plugins::http->new(%options, default_backend => 'curl');
    $self->{cache_connect} = centreon::plugins::statefile->new(%options);
    $self->{cache} = centreon::plugins::statefile->new(%options);
    
    return $self;
}

sub set_options {
    my ($self, %options) = @_;

    $self->{option_results} = $options{option_results};
}

sub set_defaults {}

sub from_fqdn_to_url {
    my $input = shift;
    # remove trailing /
    $input =~ s/\/$//;
    # if url is already complete, return
    return $input if $input =~ /^https?:\/\/[\w\.:]+\/.+$/;
    # add default auth path if nothing after fqdn
    $input .= "/oauth2/v1/token" if $input =~ /^(https?:\/\/)?[\w\.:]+$/;
    # add default auth proto if no proto given
    $input = "https://" . $input if $input !~ /^https?:\/\//;
    return $input;
}

sub check_options {
    my ($self, %options) = @_;

    $self->{$_} = $self->{option_results}->{$_} foreach qw(hostname port proto timeout auth_url api_path client_id client_secret cache_lifetime);
    $self->{output}->option_exit(short_msg => "Mandatory option 'auth-url' is missing for OneAPI authentication.") if ($self->{auth_url} eq '');

    $self->{auth_url} = from_fqdn_to_url($self->{auth_url});
    foreach (qw(client_id client_secret)) {
        $self->{output}->option_exit(short_msg => "Mandatory option '$_' is missing for OneAPI authentication.") if ($self->{$_} eq '');
        $self->{output}->option_exit(short_msg => "Option '$_' contains illegal characters.") if ($self->{$_} =~ /([\b\f\n\r\t\"\\]+)/);
    }

    $self->{cache_connect}->check_options(option_results => $self->{option_results});
    $self->{cache}->check_options(option_results => $self->{option_results});

    return 0;
}

sub settings {
    my ($self, %options) = @_;

    $self->{http}->add_header(key => 'Accept', value => 'application/json');
    $self->{http}->set_options(%{$self->{option_results}});
}

sub get_token {
    my ($self, %options) = @_;

    return $self->{token} if defined($self->{token});

    $self->settings();

    my $has_cache_file = $self->{cache_connect}->read(
        statefile => 'zdx_token_' . sha256_hex(
            $self->{auth_url}
                . '_' . $self->{client_id})
    );
    # return token stored in cache if exists after checking it is still valid
    if ($has_cache_file) {
        my $expiration = $self->{cache_connect}->get(name => 'expiration');
        if (defined($expiration) && $expiration > time() + 60) {
            $self->{token}      = $self->{cache_connect}->get(name => 'token');
            $self->{token_type} = $self->{cache_connect}->get(name => 'token_type');
            $self->{http}->add_header(key => 'Authorization', value => $self->{token_type} . ' ' . $self->{token});
            return $self->{token}
        }
    }

    # if we do not have a token or if it has to be renewed
    my $content = $self->{http}->request(
        method          => 'POST',
        full_url        => $self->{auth_url},
        post_params     => {
            'client_id'     => $self->{client_id}, 
            'client_secret' => $self->{client_secret}, 
            'grant_type'    => 'client_credentials'
        }
    );
    my $decoded_content = json_decode($content, output => $self->{output});

    $self->{output}->option_exit(short_msg => "No token found in '$content'")
        unless ($decoded_content->{access_token} || $decoded_content->{token});
    # store in $self for further requests
    $self->{token}      = $decoded_content->{access_token} // $decoded_content->{token};
    $self->{token_type} = $decoded_content->{token_type} // 'Bearer';
    # store in cache for further executions
    $self->{http}->add_header(key => 'Authorization', value => $self->{token_type} . ' ' . $self->{token});
    $self->{cache_connect}->write(data => { token => $self->{token}, token_type => $self->{token_type}, expiration => ($decoded_content->{expires_in} + time()) });

    return $self->{token};
}

sub request_devices {
    my ($self, %options) = @_;

    $self->get_token();

    my $dt_current = DateTime->now(time_zone => 'UTC');
    my $dt_end = DateTime->new(year => $dt_current->year, month => $dt_current->month, day => $dt_current->day, hour => $dt_current->hour, minute => 0, second => 0, time_zone => 'UTC');
    my $end = $dt_end->iso8601.'Z';
    my $start = $dt_end->subtract(hours => 2)->iso8601.'Z';

    my @items = ();
    my $after = '';

    while (1) {
        my $query = {
            query => '
            query ListDevices($from: DateTime!, $to: DateTime!, $first: Int!, $after: String) {
                ZDX {
                    devices(first: $first, after: $after, time_range: {from: $from, to: $to}) {
                        total_count
                        page_info { has_next_page end_cursor }
                        edges {
                            node {
                                id { value }
                                user_info {
                                    user_id { value }
                                    loc_id { value }
                                    loc_name { value }
                                    last_seen_ts
                                }
                                app_metrics {
                                    app_id { value }
                                    app_name { value }
                                    zdx_score
                                }
                                web_app_metrics {
                                    app_id { value }
                                    app_name { value }
                                    user_id { value }
                                    pft {
                                        avg
                                    }
                                }
                            } 
                        }
                    }
                }
            }',
            variables => {
                from => $start,
                to   => $end,
                first => 1000,
                after => $after
            }
        };

        my ($content) = $self->{http}->request(
            method     => 'POST',
            header => [
                'Content-Type: application/json'
            ],
            accept_encoding => 'gzip',
            url_path   => $self->{option_results}->{api_path},
            query_form_post => json_encode($query, output => $self->{output})
        );

        $self->{output}->option_exit(short_msg => "API returns empty content [code: '" . $self->{http}->get_code() . "'] [message: '" . $self->{http}->get_message() . "']")
            if is_empty($content);

        my $decoded = json_decode($content, output => $self->{output}, no_exit => 1);
        $self->{output}->option_exit(short_msg => MSG_JSON_DECODE_ERROR)
            unless $decoded;

        foreach my $node (@{$decoded->{data}->{ZDX}->{devices}->{edges}}) {
            my $item = {
                id => $node->{node}->{id}->{value},
                app_metrics => [],
                web_app_metrics => [],
                user_info => []
            };
            foreach (@{$node->{node}->{app_metrics}}) {
                push @{$item->{app_metrics}}, { app_name => $_->{app_name}->{value}, app_id => $_->{app_id}->{value}, zdx_score => $_->{zdx_score} };
            }
            foreach (@{$node->{node}->{user_info}}) {
                push @{$item->{user_info}}, { user_id => $_->{user_id}->{value}, loc_id => $_->{loc_id}->{value}, loc_name => $_->{loc_name}->{value}, last_seen_ts => $_->{last_seen_ts} };
            }
            foreach (@{$node->{node}->{web_app_metrics}}) {
                push @{$item->{web_app_metrics}}, {
                    user_id => $_->{user_id}->{value},
                    app_name => $_->{app_name}->{value},
                    app_id => $_->{app_id}->{value},
                    pft => $_->{pft}
                };
            }
            
            push @items, $item;
        }

        last if (!defined($decoded->{data}->{ZDX}->{devices}->{page_info}->{end_cursor}) || $decoded->{data}->{ZDX}->{devices}->{page_info}->{end_cursor} eq '');
        $after = $decoded->{data}->{ZDX}->{devices}->{page_info}->{end_cursor};
 
        my $remaining = $self->{http}->get_header(name => 'x-ratelimit-remaining');
        if ($remaining == 0) {
            sleep($self->{http}->get_header(name => 'x-ratelimit-reset'));
        }
    }

    return \@items;
}

sub write_cache_file {
    my ($self, %options) = @_;

    $self->{cache}->read(statefile => 'cache_zscaler_zdx_' . $options{statefile} . '_' . sha256_hex($self->{auth_url} . '_' . $self->{client_id}));
    $self->{cache}->write(data => {
        update_time => time(),
        response => $options{response}
    });
}

sub get_cache_file_response {
    my ($self, %options) = @_;

    $self->{cache}->read(statefile => 'cache_zscaler_zdx_' . $options{statefile} . '_' . sha256_hex($self->{auth_url} . '_' . $self->{client_id}));
    my $response = $self->{cache}->get(name => 'response');
    $self->{output}->option_exit(short_msg => 'Cache file missing (execute cache mode).')
        unless $response;

    my $update_time = $self->{cache}->get(name => 'update_time');
    $self->{output}->option_exit(short_msg => 'Cache file expired')
        if (time() - $self->{cache_lifetime}) > $update_time;

    return $response;
}

sub cache_devices {
    my ($self, %options) = @_;

    my $response = $self->get_devices(disable_cache => 1);
    $self->write_cache_file(
        statefile => 'devices',
        response => $response
    );

    return $response;
}

sub get_devices {
    my ($self, %options) = @_;

    return $self->get_cache_file_response(statefile => 'devices')
        if !$options{disable_cache};

    return $self->request_devices();
}

sub filter_location {
    my ($self, %options) = @_;

    foreach (@{$options{users}}) {
        if (!is_empty($options{location_id})) {
            return 0 if ($_->{loc_id} eq $options{location_id});

            return 1;
        }
      
        next if is_excluded(
            $_->{loc_name},
            $options{include_location_name},
            $options{exclude_location_name});

        return 0;
    }

    return 1;
}

sub get_apps {
    my ($self, %options) = @_;

    my $devices = $self->get_devices();

    my $apps = {};
    foreach my $dev (@$devices) {
        next if ($self->filter_location(%options, users => $dev->{user_info}));

        my $user_increment = {};

        foreach (@{$dev->{app_metrics}}) {
            next if (!is_empty($options{application_id}) && $options{application_id} ne $_->{app_id});
            next if is_excluded(
                $_->{app_name},
                $options{include_application_name},
                $options{exclude_application_name});

            if (!defined($apps->{ $_->{app_id} })) {
                $apps->{ $_->{app_id} } = {
                    id          => $_->{app_id},
                    name        => $_->{app_name},
                    score       => -1,
                    score_count => 0,
                    total_users => 0,
                    pft         => -1,
                    pft_count   => 0
                };
            }

            $apps->{ $_->{app_id} }->{score} = 0
                if ($apps->{ $_->{app_id} }->{score} == -1);

            $apps->{ $_->{app_id} }->{score} +=  $_->{zdx_score};
            $apps->{ $_->{app_id} }->{score_count}++;
            $apps->{ $_->{app_id} }->{total_users}++;
            $user_increment->{ $_->{app_id} } = 1;
        }

        foreach (@{$dev->{web_app_metrics}}) {
            next if (!is_empty($options{application_id}) && $options{application_id} ne $_->{app_id});
            next if is_excluded(
                $_->{app_name},
                $options{include_application_name},
                $options{exclude_application_name});

            if (!defined($apps->{ $_->{app_id} })) {
                $apps->{ $_->{app_id} } = {
                    id          => $_->{app_id},
                    name        => $_->{app_name},
                    score       => -1,
                    score_count => 0,
                    total_users => 0,
                    pft         => -1,
                    pft_count   => 0
                };
            }

            $apps->{ $_->{app_id} }->{pft} = 0
                if ($apps->{ $_->{app_id} }->{pft} == -1);

            $apps->{ $_->{app_id} }->{pft} +=  $_->{pft}->{avg};
            $apps->{ $_->{app_id} }->{pft_count}++;
            
            $apps->{ $_->{app_id} }->{total_users}++
                if (!defined($user_increment->{ $_->{app_id} }));
           
            $user_increment->{ $_->{app_id} } = 1;
        }
    }

    my $stats = [];
    foreach (values(%$apps)) {
        my $stat = {
            id          => $_->{id},
            name        => $_->{name},
            score       => $_->{score},
            total_users => $_->{total_users},
            pft         => $_->{pft}
        };

        $stat->{pft} = sprintf('%.2f', $stat->{pft} / $_->{pft_count})
            if ($_->{pft_count} > 0);
        $stat->{score} = sprintf('%.2f', $stat->{score} / $_->{score_count})
            if ($_->{score_count} > 0);

        push @$stats, $stat;
    }

    push @$stats, {
            id          => $options{application_id} // -1,
            name        => $options{include_application_name} //"not found",
            score       => -1,
            total_users => 0
        } unless @$stats;

    return $stats;
}

sub get_locations {
    my ($self, %options) = @_;

    my $devices = $self->get_devices();

    my $result = {};
    foreach my $dev (@$devices) {
        foreach (@{$dev->{user_info}}) {
            $result->{ $_->{loc_id} } = {
                id   => $_->{loc_id},
                name => $_->{loc_name}
            } if (!defined($result->{ $_->{loc_id} }));
       }
    }

    return [values %$result];
}

1;

__END__

=head1 NAME

Zscaler Digital Experience (ZDX) Analytics API

=head1 ANALYTICS API OPTIONS

Zscaler Digital Experience (ZDX) Analytics API

=over 8

=item B<--auth-url>

Authentication URL (or FQDN) to get a token from (mandatory).

Depends on your Zscaler customer name.

Example: C<https://company-name.zslogin.net/oauth2/v1/token> or C<company-name.zslogin.net>.

=item B<--hostname>

API URL (default: C<api.zsapi.net>). You should not need to change it.

=item B<--port>

API port (default: 443).

=item B<--proto>

Specify http if needed (default: 'https').

=item B<--api-path>

API URL path (default: '/zins/graphql')

=item B<--client-id>

Client ID for OneAPI authentication (see https://help.zscaler.com/zidentity/understanding-oneapi-authentication for more details).

=item B<--client-secret>

Client secret for OneAPI authentication (see https://help.zscaler.com/zidentity/understanding-oneapi-authentication for more details).

=item B<--timeout>

Define HTTP timeout.

=item B<--cache-lifetime>

Define the cache lifetime before raising an error (default: C<1800> seconds).

=back

=head1 DESCRIPTION

B<custom>.

=cut
