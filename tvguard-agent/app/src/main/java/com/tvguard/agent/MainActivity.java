package com.tvguard.agent;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.text.DateFormat;
import java.util.Date;

/** Remote-control-friendly diagnostics; no local history or persistent logs. */
public final class MainActivity extends Activity {
    private final Handler refreshHandler = new Handler();
    private TextView details;
    private TextView guidance;
    private Button toggle;

    private final Runnable refresh = new Runnable() {
        @Override
        public void run() {
            showSnapshot();
            refreshHandler.postDelayed(this, 2000L);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ScrollView scroller = new ScrollView(this);
        scroller.setFillViewport(true);
        scroller.setBackgroundColor(Color.rgb(16, 27, 39));
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(36, 30, 36, 30);
        scroller.addView(panel);
        addText(panel, "TVGuard 助手 · 0.1.2", 27, 0xFFFFFFFF);
        addText(panel, "Android 6 视频 App 页面观察验证版", 17, 0xFFB8C9D5);
        toggle = new Button(this);
        toggle.setAllCaps(false);
        toggle.setTextSize(18);
        toggle.setFocusable(true);
        toggle.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                boolean enable = !MonitorService.isEnabled(MainActivity.this);
                if (MonitorService.setEnabled(MainActivity.this, enable)) {
                    if (enable) {
                        startService(new Intent(MainActivity.this, MonitorService.class));
                    } else {
                        stopService(new Intent(MainActivity.this, MonitorService.class));
                    }
                }
                showSnapshot();
            }
        });
        panel.addView(toggle);
        details = addText(panel, "", 20, 0xFFEAF4F9);
        guidance = addText(panel, "", 16, 0xFFB8C9D5);
        addText(panel, "开启后运行可见的后台监测通知；无文件日志、数据库、网络权限、离线队列。", 14, 0xFFB8C9D5);
        addText(panel, "本版不连接 N1，也不参与计时、奖励、暂停或防火墙判断。", 14, 0xFFB8C9D5);
        setContentView(scroller);
    }

    private TextView addText(LinearLayout parent, String text, int sp, int color) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setPadding(0, 10, 0, 12);
        parent.addView(view);
        return view;
    }

    private String applicationName(String pkg) {
        if (pkg == null || pkg.length() == 0) return "未知 / 暂无事件";
        try {
            PackageManager manager = getPackageManager();
            ApplicationInfo info = manager.getApplicationInfo(pkg, 0);
            return manager.getApplicationLabel(info).toString() + " [" + pkg + "]";
        } catch (PackageManager.NameNotFoundException ignored) {
            return pkg;
        }
    }

    private String time(long epoch) {
        return epoch == 0 ? "尚无" : DateFormat.getDateTimeInstance().format(new Date(epoch));
    }

    private void showSnapshot() {
        MonitorService.Snapshot state = MonitorService.snapshot();
        boolean enabled = MonitorService.isEnabled(this);
        boolean access = MonitorService.hasUsageAccess(this);
        long elapsed = state.sampledMs == 0 ? -1 : System.currentTimeMillis() - state.sampledMs;
        boolean healthy = enabled && access && elapsed >= 0 && elapsed < 20000L
                && ("监测中".equals(state.state)
                    || "监测中（前台待确认）".equals(state.state));
        String freshness = healthy ? "采样正常"
                : "未确认正常采样（请查看状态与权限）";
        toggle.setText(enabled ? "停止监测" : "开始监测");
        VideoActivityHistory.Event video = state.recentVideo;
        VideoActivityHistory.Event meaningful = state.recentNonLauncher;
        StringBuilder info = new StringBuilder();
        info.append("\n权限：").append(access ? "已允许" : "未授权")
                .append("\n监测开关：").append(enabled ? "已开启" : "未开启")
                .append("\n状态：").append(state.state)
                .append("\n采样：").append(freshness);
        info.append("\n\n【最近视频 App】")
                .append("\n应用：").append(video == null ? "近期没有已识别的视频 App" :
                        applicationName(video.packageName))
                .append("\n页面：").append(video == null ? "未知" : blank(video.activityName))
                .append("\n时间：").append(video == null ? "尚无" : time(video.timeMs));
        info.append("\n\n【最近非桌面 App】")
                .append("\n应用：").append(meaningful == null ? "暂无" :
                        applicationName(meaningful.packageName))
                .append("\n页面：").append(meaningful == null ? "未知" :
                        blank(meaningful.activityName));
        info.append("\n\n当前前台：").append(applicationName(state.currentPackage))
                .append("\nActivity：").append(blank(state.currentClass))
                .append("\n\n最近前台页面切换（仅内存，最多显示6条）：");
        for (VideoActivityHistory.Event event : state.timeline) {
            String kind = VideoActivityHistory.isLauncherPackage(event.packageName) ?
                    "桌面" : VideoActivityHistory.isVideoPackage(event.packageName) ?
                    "视频" : "其他";
            info.append("\n").append(DateFormat.getTimeInstance().format(
                    new Date(event.timeMs))).append(" [").append(kind).append("] ")
                    .append(event.packageName).append(" / ")
                    .append(blank(event.activityName));
        }
        info.append("\n");
        details.setText(info.toString());
        guidance.setText(access ? "正常操作：打开视频 → 播放 → Home 返回桌面 → 从应用菜单打开助手。最近视频 App 不会被桌面覆盖；页面不等于播放/暂停。"
                : "请首次开启 ADB，在电脑执行：\n"
                + "adb shell appops set com.tvguard.agent GET_USAGE_STATS allow\n"
                + "授权后无需常驻 ADB。");
    }

    private String blank(String value) {
        return value == null || value.length() == 0 ? "未知" : value;
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Fix the real MiTV case: persisted switch is enabled while the service
        // was killed. Reopening the UI is an explicit user action, so restart it
        // once here. This is NOT a periodic/hidden keep-alive.
        if (MonitorService.isEnabled(this)) {
            startService(new Intent(this, MonitorService.class));
        }
        refreshHandler.removeCallbacks(refresh);
        refreshHandler.post(refresh);
    }

    @Override
    protected void onPause() {
        refreshHandler.removeCallbacks(refresh);
        super.onPause();
    }
}
