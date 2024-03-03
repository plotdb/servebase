`config.cfg` is a sample file for rotating server logs and organized them by year / month.

It's a parameterized file and can be transformed using `template-text`, with options shown in `sample.yaml`. Put the generated files in `/etc/logrotate.d/<your-filename>` and test with `logrotate --force /etc/logrotate.d/<your-filename>`.

following are fields of in the config yaml file:

 - `root`: path to your serverbase root
 - `logdir`: path to logrotate default output dir
 - `datedir`: path to organize logs by dates
