definition T_MINUTE() returns mathint = 60;
definition T_HOUR() returns mathint = 60 * T_MINUTE();
definition T_DAY() returns mathint = 24 * T_HOUR();
definition T_WEEK() returns mathint = 7 * T_DAY();
definition T_YEAR() returns mathint = 365 * T_DAY() + 5 * T_HOUR() + 48 * T_MINUTE() + 45;