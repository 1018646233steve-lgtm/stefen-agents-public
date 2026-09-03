package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * aiops-lab 示例应用入口。
 * 日志通过 application.yml 的 logging.file.name 输出到文件(默认 ./logs/app.log,
 * 服务器上由 systemd 注入 APP_LOG=/var/log/aiops/app.log)。
 */
@SpringBootApplication
public class DemoApplication {

    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
