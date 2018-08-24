# vayne_metric_mysql
[![Build Status](https://travis-ci.org/mon-suit/vayne_metric_mysql.svg?branch=master)](https://travis-ci.org/mon-suit/vayne_metric_mysql)

Mysql metric plugin for [vayne_core](https://github.com/mon-suit/vayne_core) monitor framework.
Checkout real monitor example to see [vayne_server](https://github.com/mon-suit/vayne_server).


## Installation

Add package to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vayne_metric_mysql, github: "mon-suit/vayne_metric_mysql"}
  ]
end
```

## Usage

```elixir
#Setup params for plugin.
params = %{"hostname" => "127.0.0.1", "username" => "root", "password" => "123456"}

#Init plugin.
{:ok, stat} = Vayne.Metric.Mysql.init(params)

#In fact, log_func will be passed by framework to record error.
log_func = fn msg -> IO.puts msg end

#Run plugin and get returned metrics.
{:ok, metrics} = Vayne.Metric.Mysql.run(stat, log_func)

#Do with metrics
IO.inspect metrics

#Clean plugin state.
:ok = Vayne.Metric.Mysql.clean(stat)
```

Support params:

* `hostname`: Mysql hostname.Required.
* `port`: Mysql port. Not required, default 3306.
* `username`: username. Not required.
* `password`: password. Not required.
* `role`: check role, "master" or "slave". Not required. Default "master".

## Support Metrics

1. All `show global status` items(could be parsed to number).
2. All `show slave status` items(could be parsed to number). Other important items:
  * `Slave_IO_Running`: `Yes` -> 1, other -> 0
  * `Slave_SQL_Running`: `Yes` -> 1, other -> 0
  * `Seconds_Behind_Master`
3. Custom items:
  * `Com_tps`: Com_commit + Com_rollback
  * `Com_qps`: Queries
  * `ConnectionPercent`: Threads_connected / max_connections
