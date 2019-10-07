Dazzler Helpers
===============

[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)

> A suite of scripts or small executables that help working with [Dazzler](https://dazzlerblog.wordpress.com/) files.


Table of Contents
-----------------

- [Install](#install)
- [Usage](#usage)
- [Maintainer](#maintainer)
- [Contributing](#contributing)
- [License](#license)


Install
--------

Just use `make && sudo make install`. For a local installtion on a per-user
basis you may use `make prefix=$HOME install`.


Usage
-----

This sections lists available commands. Run each command with `-h` to get more
information on its usage.

- **`DBln`**: Create a link to Dazzler databases and their hidden files.
- **`GenBank2DAM`**: Create a Dazzler databases from a GenBank assembly
  storing the accession in the database.
- **`BAM2DB`**: Create or append to a Dazzler database from `.bam` files
  (or any format supported by `samtools`).


Maintainer
----------

Arne Ludwig &lt;<arne.ludwig@posteo.de>&gt;


Contributing
------------

Contributions are warmly welcome. Just create an [issue][gh-issues] or [pull request][gh-pr] on GitHub. New helpers should fullfil at least the following
requirements:

- the helper must be self-documented by providing usage and help information
  by means of a `-h` command line switch
- the helper must not do any work of only `-h` is given
- the usage section of the README must have an entry for the helper  


[gh-issues]: https://github.com/a-ludi/dentist/issues
[gh-pr]: https://github.com/a-ludi/dentist/pulls


License
-------

This project is licensed under MIT License (see license in [LICENSE](./LICENSE).
