package com.example.demo.web;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;

import com.example.demo.service.FlakyService;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 故障注入 & 观察用 HTTP 接口。
 *
 * <p>重要: /api/boom、/api/flaky、/api/leak、/api/cpu 是刻意制造的"故障开关",
 * 用于生成日志异常与资源尖峰, 供 monitor 与后续 AI Agent 分析。切勿放进真实业务。</p>
 */
@RestController
@RequestMapping("/api")
public class FlakyController {

    private final FlakyService flakyService;

    public FlakyController(FlakyService flakyService) {
        this.flakyService = flakyService;
    }

    /** 健康检查(应用层) */
    @GetMapping("/ping")
    public String ping() {
        return "pong";
    }

    /** 确定性故障: 100% 抛 IllegalStateException */
    @GetMapping("/boom")
    public String boom() {
        flakyService.boom();
        return "unreachable";
    }

    /** 间歇性故障: 约 40% 概率抛 NPE */
    @GetMapping("/flaky")
    public String flaky() {
        flakyService.process("input");
        return "ok";
    }

    /** 内存增长: 每次调用 +1MB(封顶 64MB), 用于制造 OOM/内存告警 */
    @GetMapping("/leak")
    public String leak() {
        int totalMb = flakyService.leak();
        return "leaked=" + totalMb + "MB";
    }

    @GetMapping("/leak-reset")
    public String leakReset() {
        int totalMb = flakyService.leakReset();
        return "released, used=" + totalMb + "MB";
    }

    /** CPU 尖峰: /api/cpu?seconds=10, 用于触发 type=cpu 资源告警 */
    @GetMapping("/cpu")
    public String cpu(@RequestParam(defaultValue = "10") long seconds) {
        flakyService.burnCpu(seconds);
        return "burnt cpu for " + seconds + "s";
    }

    /** JVM 堆内存快照(供 Agent 取证, 与 actuator 指标互为补充) */
    @GetMapping("/mem")
    public String mem() {
        MemoryMXBean mx = ManagementFactory.getMemoryMXBean();
        MemoryUsage heap = mx.getHeapMemoryUsage();
        MemoryUsage nonHeap = mx.getNonHeapMemoryUsage();
        return String.format("heap used=%dMB max=%dMB | nonHeap used=%dMB",
                heap.getUsed() / 1024 / 1024, heap.getMax() / 1024 / 1024,
                nonHeap.getUsed() / 1024 / 1024);
    }
}
