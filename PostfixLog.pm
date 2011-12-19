package PostfixLog;
#
# PostfixLog - a Collectd Plugin
# Copyright (C) 2011 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use Fcntl qw (:flock);

use Collectd qw( :all );

#
# configure the plugin
#

my $config =
{
	LogFile => '/var/log/mail.log', # path to the access log file of apache
	TmpFile => '/tmp/collectd-postfixlog.tmp', # path for the temporary file of this plugin
};

#
# plugin code itself
#  touch it at your own risk
#

our $VERSION = '0.10';

my $dataset =
[
	{
		name => 'accepted',
		type => Collectd::DS_TYPE_GAUGE,
		min => 0,
		max => 65535,
	},
	{
		name => 'bounced',
		type => Collectd::DS_TYPE_GAUGE,
		min => 0,
		max => 65535,
	},
	{
		name => 'connections',
		type => Collectd::DS_TYPE_GAUGE,
		min => 0,
		max => 65535,
	},
	{
		name => 'received',
		type => Collectd::DS_TYPE_GAUGE,
		min => 0,
		max => 65535,
	},
	{
		name => 'sent',
		type => Collectd::DS_TYPE_GAUGE,
		min => 0,
		max => 65535,
	},
	{
		name => 'size',
		type => Collectd::DS_TYPE_GAUGE,
		min => 0,
		max => 65535,
	},
];

sub PostfixLog_init
{
	return 1;
}

sub write_tmpfile
{
	my $last_log_line = shift;

	if (open(TMPFILE, ">".$config->{'TmpFile'}))
	{
		flock(TMPFILE, LOCK_EX);
		print TMPFILE $last_log_line;
		flock(TMPFILE, LOCK_UN);
		close(TMPFILE);
		return 1;
	}
	else
	{
		Collectd::plugin_log(Collectd::LOG_ERR, "Cannot open $config->{'TmpFile'} for writing.");
	}
	return 0;
}

sub read_tmpfile
{
	if (-e $config->{'TmpFile'})
	{
		open(TMPFILE, $config->{'TmpFile'}) || return "";
		my $last_log_line = <TMPFILE>;
		close(TMPFILE);
		return $last_log_line;
	}
	return "";
}

sub PostfixLog_read
{
	my $lastline = read_tmpfile();
	open(FILE, $config->{'LogFile'});
	my @lines = <FILE>;
	close(FILE);
	write_tmpfile($lines[-1]);

	# splicing already evaluated lines from logfile
	my $index = 0;
	for (my $i = 0; $i < scalar @lines; $i++)
	{
		if ($lines[$i] eq $lastline)
		{
			$index = $i;
			last;
		}
	}
	$index++;
	splice(@lines, 0, $index);

	# initializing all stats with zeros
	my %stats = (
		'accepted' => 0,
		'bounced' => 0,
		'connections' => 0,
		'received' => 0,
		'sent' => 0,
		'size' => 0,
	);

	foreach (@lines)
	{
		if ($_ =~ /\s+connect\s+from/)
		{
			$stats{'connections'}++;
		}
		elsif ($_ =~ /relay=([\w+\[\]\:]+),\sdelay=([0-9\.]+),\s.+,\sstatus=(\w+)/)
		{
			$stats{'bounced'}++ if ($3 eq 'bounced');
			$stats{'accepted'}++ if ($3 eq 'sent');
			if ($1 eq 'local')
			{
				$stats{'received'}++;
			}
			else
			{
				$stats{'sent'}++;
			}
		}
		elsif ($_ =~ /size=(\d+)/)
		{
			$stats{'size'} += $1;
		}
	}

	my $vl = {};
	$vl->{'values'} = [ $stats{'accepted'}, $stats{'bounced'}, $stats{'connections'}, $stats{'received'}, $stats{'sent'}, $stats{'size'}, ];
	$vl->{'plugin'} = 'PostfixLog';
	Collectd::plugin_dispatch_values('PostfixLog', $vl);

	return 1;
}

sub PostfixLog_write
{
	my $type = shift;
	my $ds = shift;
	my $vl = shift;

	if (scalar (@$ds) != scalar (@{$vl->{'values'}}))
	{
		Collectd::plugin_log(Collectd::LOG_ERR, "DS number does not match values length");
		return;
	}
	for (my $i = 0; $i < scalar (@$ds); ++$i)
	{
		print "$vl->{'host'}: $vl->{'plugin'}: ";
		if (defined $vl->{'plugin_instance'})
		{
			print "$vl->{'plugin_instance'}: ";
		}
		print "$type: ";
		if (defined $vl->{'type_instance'})
		{
			print "$vl->{'type_instance'}: ";
		}
		print "$vl->{'values'}->[$i]\n";
	}
	if (scalar (@$ds) != scalar (@{$vl->{'values'}}))
	{
		Collectd::plugin_log(Collectd::LOG_WARNING, "DS number does not match values length");
		return;
	}

	return 1;
}

sub PostfixLog_log
{
	return 1;
}

sub PostfixLog_shutdown
{
	return 1;
}

Collectd::plugin_register(Collectd::TYPE_DATASET, 'PostfixLog', $dataset);
#Collectd::plugin_register(Collectd::TYPE_CONFIG, "PostfixLog", $config);
Collectd::plugin_register(Collectd::TYPE_INIT, "PostfixLog", \&PostfixLog_init);
Collectd::plugin_register(Collectd::TYPE_READ, "PostfixLog", "PostfixLog_read");
Collectd::plugin_register(Collectd::TYPE_WRITE, "PostfixLog", "PostfixLog_write");
Collectd::plugin_register(Collectd::TYPE_LOG, "PostfixLog", "PostfixLog_log");
Collectd::plugin_register(Collectd::TYPE_SHUTDOWN, "PostfixLog", "PostfixLog_shutdown");

1;
