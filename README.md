
<!--#echo json="package.json" key="name" underline="=" -->
anno-doi-bot-23
===============
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
DOI registration bot for web annotations, optimized for use by the Heidelberg
University Library.
<!--/#echo -->



Installation
------------

1.  Ensure you have the prerequisites:
    * Ubuntu 22.04 or later
    * Node.js v20 or later
1.  Clone this repo and chdir to your clone's top directory.
1.  Run `npm install .`
1.  Continue at chapter "Configuration".



Configuration
-------------

* You can modify the configuration at any time.
  Changes will take effect the next time the DOI bot runs.
* The available config options can be found (not: modified)
  in the [default settings file](`funcs/cfg.default.rc`).
* To customize configuration, create a subdirectory named `config`,
  and in there, one or more text files whose name ends in `.rc`
  (e.g. `basics.rc`).
  * All these files are read in your locale's sorting order,
    which may or may not be case-sensitive.
    For reliable ordering, start all filenames with a fixed number of
    digits, e.g. `010_basics.rc`, `023_doi_format.rc`, `080_hotfixes.rc`.



Usage
-----

* manually: Run `./doibot.sh`
* via cron or a similar scheduler: Configure a schedule that runs
  `/path/to/this/repo/doibot.sh cron_task`



Notes on the bot's behavior
---------------------------

* In case the bot receives any unexpected reply from the DOI registry,
  it gives up the entire run. This is intentional, because an unexpected
  reply could mean the registry is under heavy load, or the bot might even
  be misbehaving due to a config error.
  In both cases, we should avoid annoying the registry further until
  an admin has reviewed the error message.





<!--#toc stop="scan" -->



Known issues
------------

* Needs more/better tests and docs.




&nbsp;


License
-------
<!--#echo json="package.json" key=".license" -->
MIT
<!--/#echo -->
