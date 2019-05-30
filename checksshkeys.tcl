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

expect {ltrkarkvm066:[dD]igC[uU][sS][tT] \$}

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

expect {ltrkarkvm066:[dD]igC[uU][sS][tT] \$}

send "ssh g9983898@ltrkarkvm408\n"

expect {
    "(yes/no)" {
        send "yes\n"     
        exp_continue
    }

    "ltrkarkvm408:~" {
        send "exit\n"
    }

    timeout {
        puts "Timeout"
    }
}

expect {ltrkarkvm066:[dD]igC[uU][sS][tT] \$}
