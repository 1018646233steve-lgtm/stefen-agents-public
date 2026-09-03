package com.example.demo.service;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

import org.springframework.stereotype.Service;

/**
 * 故障注入服务 —— 供监控/AI Agent 测试用, 不是"正常业务代码"。
 */
@Service
public class FlakyService {

    /** /api/boom 每次调用必抛异常(确定性故障: 用于验证监控一定能抓到) */
    public void boom() {
        throw new IllegalStateException("boom");
    }

    /** /api/flaky 约 40% 概率抛 NPE(间歇性故障: 用于验证去抖与聚合) */
    public void process(String input) {
        if (ThreadLocalRandom.current().nextInt(100) < 40) {
            // NPE 的直接原因: 未判空
            String s = null;
            s.length();
        }
        // 正常路径
    }

    /** 模拟内存泄漏: 累积引用大对象(上限 64MB, 保护开发机不被拖垮) */
    private static final List<byte[]> LEAK = new ArrayList<>();
    private static final int CHUNK_MB = 1;
    private static final int LEAK_CAP_MB = 64;

    public synchronized int leak() {
        if (LEAK.size() * CHUNK_MB >= LEAK_CAP_MB) {
            throw new IllegalStateException("leak cap reached (" + LEAK_CAP_MB + "MB), 调用 /api/leak-reset 释放");
        }
        LEAK.add(new byte[CHUNK_MB * 1024 * 1024]);
        return LEAK.size() * CHUNK_MB;
    }

    public synchronized int leakReset() {
        LEAK.clear();
        return 0;
    }

    /** 模拟 CPU 尖峰: 忙等 seconds 秒(用于触发 type=cpu 的资源告警) */
    public void burnCpu(long seconds) {
        long deadline = System.nanoTime() + seconds * 1_000_000_000L;
        while (System.nanoTime() < deadline) {
            // busy loop
        }
    }
}
