#!/usr/bin/expect -f

spawn bash

send "ssh admin@enterprise-dev.windstream.com\n"

expect {
    "yes/no" {
        send "yes\n"
        exp_continue
    }

    "admin@enterprise-dev ~" {
        send "exit\n"
    }
}

expect {ltrkarkvm066:DigCust \$}

send "ssh admin@enterprise.windstream.com\n"

expect {
    "(yes/no)" {
        send "yes\n"     
        exp_continue
    }

    "admin@enterprise ~" {
        send "exit\n"
    }

    timeout {
        puts "Timeout"
    }
}

expect {ltrkarkvm066:DigCust \$}
