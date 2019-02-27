cbf-routing-profiles
====================

Experimental routing profiles for OSRM, together with some scripts to compile and
run a site with multiple routing profiles.

Installation
------------

* get OSRM (http://project-osrm.org) and compile.
  Currently version v5.18 is needed.

* get OSRM website (https://github.com/DennisSchiefer/Project-OSRM-Web)

* get OSM data, for example the planet or an extract from Geofabrik

* create configuration file for the compilation environment, see `profiles.conf.example`

* add additional profiles to OSRM website, see `WebContent/OSRM.config.js`

* adapt look and feel of OSRM website to your liking

* compile OSRM profiles:

    ./compile_profiles.sh -c your_profiles.conf

* start servers:

    ./start-servers.sh your_profiles.conf

* when updating, first recompile the profiles, then reinitialise the server:

    ./compile_profiles.sh your_profiles.conf &&
    ./start-servers.sh -c your_profiles.conf

License
-------

The profiles use code from the sample profiles included in osrm-backend

Copyright (c) 2018, Project OSRM contributors
                    cbf-routing-profiles contributors
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list
of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this
list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
