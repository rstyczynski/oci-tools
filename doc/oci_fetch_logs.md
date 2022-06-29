# OCI fetch logs 

OCI log collecting subsystem makes it possible to export logs, however with limitation of exporting one page with maximum of 500 records. It looks like a big gap in the console, making it useless in some of production like situations.

Limitations of OCI console are eliminated by using OCI CLI tool which implements handy wrapper over OCI API. This tools is not easy to use due to pagination, which requires several invocations to collect full set of expected logs.

oci_fetch_logs.sh script fills the gap by providing easy to use tool to export full set of log records related to specified search query. oci_fetch_logs.sh is a wrapper over 'oci logging-search search-logs' OCI CLI.

oci_fetch_logs.sh works in one-shot manner, providing chain mode exporting logs from the most recent entries. Chain mode makes it possible to download full set of logs spanning multiple script invocations. This mode may be used from cron to sync required logs to file system.  

oci_fetch_logs.sh is part of oci-tools, and uses some of tools as config.sh to persist static parameters.

## Prerequisites
To use oci_fetch_logs.sh you need to configure OCI CLI, own OCI access credentials with configured API KEY, and deploy necessary OCI policies. oci_fetch_logs.sh must be used with oci-tools, as it uses some of shared libraries (named_exit, config.sh). The best is to use it from directory with complete oci-tools package. Having this you can export logs from CLI. 

## Configuration
First time use requires to provide three parameters which identifies target log: 
- compartment ocid,
- log group ocid,
- log ocid.

You can provide them as command line arguments. When not provided oci_fetch_logs.sh will ask for them, to store provided identifiers in configuration file. Once stored this data will be read from configuration file during further script invocations. 

```
oci_fetch_logs.sh \
--compartment_ocid=ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v... \
--loggroup_ocid=ocid1.loggroup.oc1.eu-frankfurt-1.amaaaaaakb7hq2ia5... \
--log_ocid=ocid1.log.oc1.eu-frankfurt-1.amaaaaaakb7hq2iar7dqr5375w7r6j...
```

Use OCI console to discover compartment ocid, log group ocid, and log ocid. 

> Hint. Runing CLI at OCI compute node, you can get compartment ocid from meta information service.

```
compartment_ocid=$(curl  --connect-timeout 1 -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
```

Default configuration name is oci_fetch_logs, what you will see in config file (/etc/oci_fetch_logs.config or ~/.oci_fetch_logs/config) and in the name of files with logs.

## First data fetch
By default oci_fetch_logs.sh collects all log records from recent hour to write them to current directory. 

```
oci_fetch_logs_1649747785437_1of3.json
oci_fetch_logs_1649747785437_2of3.json
oci_fetch_logs_1649747785437_3of3.json
oci_fetch_logs_1649747785437.info
oci_fetch_logs.info
```

Data files are named usng config name, data collection timestamp, and page information. Next to set of json files you get two *.info fles. The one with timestamp describes given log fetch session, and the one with config name describes latest fetch. This file is used by next oci_fetch_logs.sh invocation in chain mode, to be aware of starting timestamp for next fetch session. 

## Specify data directory
By default oci_fetch_logs.sh writes data to current directory. You can specify target directory by applying --data_dir argument.

```
oci_fetch_logs.sh --data_dir ~/logs
```

## Specify search query
Search query parameter is conveyed to 'oci logging-search search-logs' OCI CLI command, so you can specify any query available for this utility. 


Exemplary invocations:

```
oci_fetch_logs.sh  --search_query 200
oci_fetch_logs.sh  --search_query data.backendStatusCode=200
oci_fetch_logs.sh  --search_query "logContent=\'*TrackDelivery*\'"
```

## Specify date range
By default oci_fetch_logs.sh gets last hour of logs. You can control time range by providing time arguments for start and end in RFC3339 format. This is controlled by regular OCI CLI arguments --time-start and --time-end.

```
oci_fetch_logs.sh  \
--time_start $(date +%Y-%m-%d\T%H:%M:%SZ -u -d "15 minutes ago") \
--time_end $(date +%Y-%m-%d\T%H:%M:%SZ -u -d "5 minutes ago")
```

In addition you can specify time range in UTC timestamps using arguments --timestamp_start and --timestamp_end.

```
oci_fetch_logs.sh  \
--timestamp_start $(date +%s -u -d "15 minutes ago")000Z \
--timestamp_end $(date +%s -u -d "5 minutes ago")000Z
```

## Practical use cases
### Write data to date directory
oci_fetch_logs.sh may be instructed to write data to sub directory reflecting current date. This logic is added to enable oci_fetch_logs.sh to work in continuous mode from cron table w/o additional worries. 

```
oci_fetch_logs.sh --date_dir
```

Each day logs are automatically stroed in subdirectory with the name of current day in format YYYY-MM-DD. It makes easy to locate logs, protects against writing too much files in single directory, and makes easy to purge old logs.

### Chain mode
To collect all recent logs by multiple invocations of oci_fetch_logs.sh you specify --continue argument. In this mode oci_fetch_logs.sh reads timestamp of latest log entry, adds 1ms and use as --timestamp_start. 

```
oci_fetch_logs.sh --continue
```

Note that timestamp is taken from *.info file, which contains information about log fetch session for given configuration id. In case recent directory is different than data directory, use --recent_dir to let oci_fetch_logs.sh know where to look for info file.

```
oci_fetch_logs.sh --recent_dir ~/old_logs --continue
```

When oci_fetch_logs.sh works with date_dir option in continue mode, and info file is not found in current date directory, oci_fetch_logs.sh looks for info file in directory reflecting previous day. When info file is not found in previous day directory, regular behavior of 1 hour ago is applied. This logic is added to enable oci_fetch_logs.sh to work in continuous mode from cron table w/o additional worries. 

```
oci_fetch_logs.sh --date_dir --continue
```

### Multiple config files
As single configuration describes one specific log, you can name configuration set by cfg_id argument. This argument sets configuration name to specified one. 

```
oci_fetch_logs.sh \
--cfg_id LB_PROD \
--compartment_ocid=ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v4wizepnfosvc... \
--loggroup_ocid=ocid1.loggroup.oc1.eu-frankfurt-1.amaaaaaakb7hq2ia5kwo4b24umk6z6... \
--log_ocid=ocid1.log.oc1.eu-frankfurt-1.amaaaaaakb7hq2iar7dqr5375w7r6j...
```

Next time invocation should be done with config name, to read ocids from the configuration.

```
oci_fetch_logs.sh --cfg_id LB_PROD
```

### Temp directory
oci_fetch_logs.sh uses temp directory to write first fetched page. By default created tmp directory in user's home. To change tmp directory use --tmp_dir argument.

### Debug
Enable debug information by adding debug option. This mode presents information useful during e.g. veryfing search query or time stamps.

```
oci_fetch_logs.sh --debug
```

# Error codes
oci_fetch_logs.sh returns exit code to inform about sucess or error conditions.

Sucess is manifested by two ways with exit code 0:
* No data to fetch.
* Data expected, but no data to fetch.

Errors are described by exit codes > 0:
1. Script bin directory unknown.
2. Required tools not available.
3. Query execuion error.
4. OCI client execution failed.
5. Trying to fetch 10+ pages than expected.
6. Directory not writable.


