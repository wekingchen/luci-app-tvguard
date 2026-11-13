package com.tvguard.agent;

import android.app.Activity;
import android.content.Intent;
import android.content.ActivityNotFoundException;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.provider.Settings;
import android.view.View;
import android.view.KeyEvent;
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
    private TextView healthSummary;
    private TextView guidance;
    private Button toggle;
    private Button changeAddressButton;
    private Button autoPairButton;
    private Button accessibilityButton;
    private int remoteSelectedIndex = 2;
    private TextView bridgeStatus;
    private TextView endpointDisplay;
    private TextView remoteDebug;

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
        // Android 6 TV navigation can be consumed by ScrollView before
        // Activity.dispatchKeyEvent sees it; intercept at the container.
        ScrollView scroller = new ScrollView(this) {
            @Override
            public boolean dispatchKeyEvent(KeyEvent event) {
                if (handleRemoteKey(event)) return true;
                return super.dispatchKeyEvent(event);
            }
        };
        scroller.setFillViewport(true);
        scroller.setBackgroundColor(Color.rgb(16, 27, 39));
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(32, 18, 32, 18);
        scroller.addView(panel);
        addText(panel, "TVGuard 助手 · 0.3.2", 24, 0xFFFFFFFF);
        addText(panel, "Android 6 前台上下文 + UI 结构诊断版", 14, 0xFFB8C9D5);
        toggle = new Button(this);
        toggle.setAllCaps(false);
        styleActionButton(toggle);
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
        healthSummary = addText(panel, "采样状态：等待启动", 14, 0xFFB8C9D5);

        addText(panel, "N1 联动 · 仅旁路观察，不改变实际计时", 16, 0xFFEAF4F9);
        endpointDisplay = addText(panel, "N1 地址：" + BridgeClient.endpoint(this), 14, 0xFFB8C9D5);

        final Button changeAddress = new Button(this);
        styleActionButton(changeAddress);
        changeAddress.setText("修改 N1 地址（遥控器数字键盘）");
        changeAddress.setFocusable(true);
        changeAddress.setId(View.generateViewId());
        changeAddress.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                TvAddressEditor.show(MainActivity.this, new TvAddressEditor.Callback() {
                    @Override public void onSaved(String value) {
                        endpointDisplay.setText("N1 地址：" + value);
                        showSnapshot();
                    }
                });
            }
        });
        panel.addView(changeAddress);
        changeAddressButton = changeAddress;

        final Button autoPair = new Button(this);
        styleActionButton(autoPair);
        autoPair.setText("自动配对 N1（无需输入密钥）");
                autoPair.setFocusable(true);
        autoPair.setFocusableInTouchMode(true);
        autoPair.setId(View.generateViewId());
        autoPair.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                autoPair.setEnabled(false);
                BridgeClient.autoPair(MainActivity.this, new BridgeClient.PairingCallback() {
                    @Override public void onResult(boolean success, String message) {
                        autoPair.setEnabled(true);
                        if (success && !MonitorService.isEnabled(MainActivity.this) &&
                                MonitorService.setEnabled(MainActivity.this, true)) {
                            startService(new Intent(MainActivity.this, MonitorService.class));
                        }
                        bridgeStatus.setText("N1：" + message);
                    }
                });
            }
        });
        panel.addView(autoPair);
        autoPairButton = autoPair;

        final Button accessibility = new Button(this);
        styleActionButton(accessibility);
        accessibility.setText("打开无障碍设置（可选 UI 结构观察）");
        accessibility.setFocusable(true);
        accessibility.setId(View.generateViewId());
        accessibility.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
                try {
                    if (getPackageManager().resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                        startActivity(intent);
                    } else {
                        bridgeStatus.setText("系统未提供无障碍设置入口；请使用 ADB/系统级方式启用 UI 结构观察");
                    }
                } catch (ActivityNotFoundException ignored) {
                    bridgeStatus.setText("系统未提供无障碍设置入口；请使用 ADB/系统级方式启用 UI 结构观察");
                }
            }
        });
        panel.addView(accessibility);
        accessibilityButton = accessibility;
        toggle.setId(View.generateViewId());
        toggle.setNextFocusDownId(changeAddress.getId());
        changeAddress.setNextFocusUpId(toggle.getId());
        changeAddress.setNextFocusDownId(autoPair.getId());
        autoPair.setNextFocusUpId(changeAddress.getId());
        autoPair.setNextFocusDownId(accessibility.getId());
        accessibility.setNextFocusUpId(autoPair.getId());
        bridgeStatus = addText(panel, "", 14, 0xFFB8C9D5);
        remoteDebug = addText(panel, "遥控器：首次打开直接按确定进行自动配对", 13, 0xFFB8C9D5);
        details = addText(panel, "", 15, 0xFFEAF4F9);
        guidance = addText(panel, "", 14, 0xFFB8C9D5);
        addText(panel, "开启后由系统恢复任务维持监测；仅向 N1 发送当前状态，无文件日志、数据库或离线队列。", 12, 0xFFB8C9D5);
        addText(panel, "UI 结构观察为可选诊断：不读取/上传文字内容，只统计结构并生成摘要；当前不参与计时、奖励、暂停或防火墙判断。", 12, 0xFFB8C9D5);
        addText(panel, "本版连接 N1 仅用于观察，不参与计时、奖励、暂停或防火墙判断。", 12, 0xFFB8C9D5);
        setContentView(scroller);
        // First-launch focus always lands on the only button needed for pairing.
        // The user does not need TV text input or DPAD_DOWN to begin.
        autoPairButton.requestFocusFromTouch();
        autoPairButton.requestFocus();
    }

    private void styleActionButton(Button button) {
        button.setAllCaps(false);
        button.setTextSize(16);
        button.setMinHeight(48);
        button.setPadding(18, 4, 18, 4);
    }

    private TextView addText(LinearLayout parent, String text, int sp, int color) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setPadding(0, 5, 0, 6);
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
        String accessState = MonitorService.usageAccessState(this);
        boolean access = "allowed".equals(accessState);
        long elapsed = state.sampledMs == 0 ? -1 : System.currentTimeMillis() - state.sampledMs;
        boolean healthy = enabled && elapsed >= 0 && elapsed < 20000L;
        String freshness = healthy ? "采样正常"
                : "未确认正常采样（请查看状态与权限）";
        if (healthSummary != null) healthSummary.setText(
                "监测状态：" + state.state + " · " + freshness +
                " · 系统恢复：" + (RecoveryScheduler.isScheduled(this) ? "已安排" : "未安排"));
        toggle.setText(enabled ? "停止监测" : "开始监测");
        long ack = BridgeClient.ackAt();
        bridgeStatus.setText("N1：" + BridgeClient.state() +
                "  · 最近接收：" + (ack == 0 ? "尚无" : time(ack)));
        ForegroundActivityHistory.Event meaningful = state.recentNonLauncher;
        StringBuilder info = new StringBuilder();
        info.append("使用情况权限判断：").append(accessState)
                .append("\n监测开关：").append(enabled ? "已开启" : "未开启")
                .append("\n状态：").append(state.state)
                .append("\n采样：").append(freshness)
                .append("\n前台来源：").append(state.foregroundSource)
                .append("\n前台诊断：").append(state.foregroundStatus)
                .append("\nUI 结构观察：")
                .append(UiStructureAccessibilityService.isConnected() ? "已启用" : "未启用");
        info.append("\n\n【最近非桌面 App】")
                .append("\n应用：").append(meaningful == null ? "暂无" :
                        applicationName(meaningful.packageName))
                .append("\n页面：").append(meaningful == null ? "未知" :
                        blank(meaningful.activityName));
        info.append("\n\n当前前台：").append(applicationName(state.currentPackage))
                .append("\nActivity：").append(blank(state.currentClass))
                .append("\n\n最近前台页面切换（仅内存，最多显示6条）：");
        for (ForegroundActivityHistory.Event event : state.timeline) {
            String kind = ForegroundActivityHistory.isLauncherPackage(event.packageName) ?
                    "桌面" : "应用";
            info.append("\n").append(DateFormat.getTimeInstance().format(
                    new Date(event.timeMs))).append(" [").append(kind).append("] ")
                    .append(event.packageName).append(" / ")
                    .append(blank(event.activityName));
        }
        info.append("\n");
        details.setText(info.toString());
        if ("usage_events".equals(state.foregroundSource)) {
            guidance.setText("已取得 UsageEvents 前台上下文。助手不维护视频 App 白名单；播放/暂停仍由 N1 根据网络与时序证据统一学习。");
        } else if ("usage_stats".equals(state.foregroundSource)) {
            guidance.setText("当前仅取得应用包名，Activity 未确认。N1 只会把它用于播放方向辅助，不会据此判定首页或暂停免计时。");
        } else if (!access) {
            guidance.setText("系统权限判断为 " + accessState + "。可在方便连接 ADB 时执行：\n"
                    + "adb shell appops set com.tvguard.agent GET_USAGE_STATS allow\n"
                    + "未确认权限期间 N1 仍会保守计时。");
        } else {
            guidance.setText("Agent 在线，但当前没有可靠前台上下文。诊断会随心跳上报 N1，不写电视本地日志。");
        }
    }

    private String blank(String value) {
        return value == null || value.length() == 0 ? "未知" : value;
    }

    // All three remote buttons use a deterministic selection index.
    // We consume navigation at ScrollView before child focus-search/scroll.
    private boolean handleRemoteKey(KeyEvent event) {
        int code = event.getKeyCode();
        boolean navigation = code == KeyEvent.KEYCODE_DPAD_UP ||
                code == KeyEvent.KEYCODE_DPAD_DOWN;
        boolean activate = code == KeyEvent.KEYCODE_DPAD_CENTER ||
                code == KeyEvent.KEYCODE_ENTER ||
                code == KeyEvent.KEYCODE_NUMPAD_ENTER;
        if (!navigation && !activate) return false;
        if (event.getAction() == KeyEvent.ACTION_UP) return true;
        if (event.getAction() != KeyEvent.ACTION_DOWN || event.getRepeatCount() > 0)
            return true;
        Button[] choices = { toggle, changeAddressButton, autoPairButton, accessibilityButton };
        if (navigation) {
            // At the edges, let ScrollView consume the key so diagnostics below
            // the action buttons remain reachable with an ordinary TV remote.
            if ((code == KeyEvent.KEYCODE_DPAD_DOWN && remoteSelectedIndex == choices.length - 1) ||
                    (code == KeyEvent.KEYCODE_DPAD_UP && remoteSelectedIndex == 0)) {
                return false;
            }
            remoteSelectedIndex = Math.max(0, Math.min(choices.length - 1,
                    remoteSelectedIndex + (code == KeyEvent.KEYCODE_DPAD_DOWN ? 1 : -1)));
            Button selected = choices[remoteSelectedIndex];
            if (selected != null) {
                selected.requestFocus();
                if (remoteDebug != null) remoteDebug.setText(
                        "遥控器：已选中 " + selected.getText());
            }
            return true;
        }
        Button selected = choices[remoteSelectedIndex];
        if (selected != null && selected.isEnabled()) selected.performClick();
        return true;
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
