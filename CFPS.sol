// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library CFPS {
    string constant STR_NOT_AUTHORIZED = "You are not authorized to perform this action";
    string constant STR_NO_FUNDS = "No funds to withdraw";
    string constant STR_CLOSED_NOOP = "This operation cannot be performed on closed campaign";
    string constant STR_CAMPAIGN_CLOSED = "This campaign is closed";
    string constant STR_STILL_RUNNING = "This campaign is still running";
    string constant STR_CAMPAIGN_LIMIT = "Only 1 campaign at a time";
    string constant STR_INVALID_PERIOD = "Invalid period";
    string constant STR_INVALID_START = "Campaign start date is in the past";
    string constant STR_TARGET_TOO_LOW = "Campaign target value is too low";
    string constant STR_INVALID_ADDRESS = "Specified address is not valid";
    string constant STR_MINIMUM_DONATION = "Minimal donation is 100000 Wei";
    string constant STR_NOT_STARTED = "Campaign has not started";
    string constant STR_ENDED = "Campaign has ended";
    string constant STR_INVALID_DATA = "Specified data is not valid";
}
