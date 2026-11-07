/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module com.appversion;

import std.string : strip;

// Application/editor release identity only; song format and music driver
// compatibility have separate owners.
enum string APP_NAME = "CheeseCutter";
enum string APP_VERSION = strip(import("VERSION"));
enum string APP_REVISION_MARKER = "R";
enum string APP_EDITION = "Hypercut";
enum string APP_DISPLAY_VERSION = APP_VERSION ~ APP_REVISION_MARKER ~
	": " ~ APP_EDITION;
enum string APP_DISPLAY_NAME = APP_NAME ~ " " ~ APP_DISPLAY_VERSION;
