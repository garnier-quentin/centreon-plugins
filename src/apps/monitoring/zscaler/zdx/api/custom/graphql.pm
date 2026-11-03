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

    $self->{$_} = $self->{option_results}->{$_} foreach qw(hostname port proto timeout auth_url api_path client_id client_secret);
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

    my $query = {
        query => '
        query ListDevices($from: DateTime!, $to: DateTime!, $first: Int!, $after: String) {
            ZDX {
                devices(first: $first, after: $after, time_range: {from: $from, to: $to}) {
                    total_count
                    page_info { has_next_page end_cursor }
                    edges { node { id { value } name { value } profile { os_name zdx_version } } }
                }
            }
        }',
        variables => {
            from => '2026-02-11T00:00:00Z',
            to   => '2026-02-11T01:00:00Z',
            first => 1000,
            after => undef
        }
    };

    my ($content) = $self->{http}->request(
        method     => 'POST',
        header => [
            'Content-Type: application/json',
            'Accept-Encoding: gzip'
        ],
        url_path   => $self->{option_results}->{api_path},
        query_form_post => json_encode($query, output => $self->{output})
    );

    $self->{output}->option_exit(short_msg => "API returns empty content [code: '" . $self->{http}->get_code() . "'] [message: '" . $self->{http}->get_message() . "']")
        if is_empty($content);

    my $decoded = json_decode($content, output => $self->{output}, no_exit => 1);
    $self->{output}->option_exit(short_msg => MSG_JSON_DECODE_ERROR)
        unless $decoded;

    return $decoded;
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

sub get_apps {
    my ($self, %options) = @_;

    my $devices = $self->get_devices();
}

sub get_locations {
    my ($self, %options) = @_;

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
