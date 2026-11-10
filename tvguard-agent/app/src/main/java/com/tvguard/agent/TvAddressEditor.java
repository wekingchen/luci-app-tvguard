package com.tvguard.agent;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.view.View;
import android.widget.Button;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.net.URI;

/**
 * Self-contained numeric IPv4 editor; does not require Xiaomi TV IME, keyboard
 * app, touch screen, Accessibility Service, ADB, logs or extra permissions.
 */
final class TvAddressEditor {
    interface Callback {
        void onSaved(String endpoint);
    }

    private TvAddressEditor() { }

    static void show(final Activity activity, final Callback callback) {
        String current = "192.168.101.99";
        try {
            URI parsed = new URI(BridgeClient.endpoint(activity));
            if (parsed.getHost() != null) current = parsed.getHost();
        } catch (Exception ignored) { }
        final StringBuilder address = new StringBuilder(current);
        final LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(24, 16, 24, 16);

        final TextView preview = new TextView(activity);
        preview.setTextSize(24);
        preview.setTextColor(Color.WHITE);
        preview.setPadding(10, 12, 10, 16);
        preview.setText(address.toString());
        layout.addView(preview);

        final TextView instructions = new TextView(activity);
        instructions.setText("用遥控器方向键选择数字并按确定；不需要输入法。");
        instructions.setTextSize(16);
        instructions.setTextColor(0xFFE1E7EC);
        instructions.setPadding(6, 0, 6, 16);
        layout.addView(instructions);

        final GridLayout grid = new GridLayout(activity);
        grid.setColumnCount(3);
        layout.addView(grid);
        final String[] symbols = {
                "1", "2", "3", "4", "5", "6", "7", "8", "9",
                ".", "0", "删除", "清空"
        };
        Button focusButton = null;
        for (final String symbol : symbols) {
            final Button button = new Button(activity);
            button.setAllCaps(false);
            button.setText(symbol);
            button.setTextSize(17);
            button.setFocusable(true);
            button.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    if ("删除".equals(symbol)) {
                        if (address.length() > 0) address.deleteCharAt(address.length() - 1);
                    } else if ("清空".equals(symbol)) {
                        address.setLength(0);
                    } else if (address.length() < 15) {
                        address.append(symbol);
                    }
                    preview.setText(address.length() == 0 ? "（请输入 N1 IPv4）" :
                            address.toString());
                }
            });
            GridLayout.LayoutParams params = new GridLayout.LayoutParams();
            params.width = 0;
            params.height = GridLayout.LayoutParams.WRAP_CONTENT;
            params.columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f);
            button.setLayoutParams(params);
            grid.addView(button);
            if (focusButton == null) focusButton = button;
        }
        final AlertDialog dialog = new AlertDialog.Builder(activity)
                .setTitle("修改 N1 地址")
                .setView(layout)
                .setPositiveButton("保存地址", null)
                .setNegativeButton("取消", null)
                .create();
        dialog.setOnShowListener(new android.content.DialogInterface.OnShowListener() {
            @Override public void onShow(android.content.DialogInterface ignored) {
                Button save = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
                save.setOnClickListener(new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        String value = "http://" + address.toString() +
                                "/cgi-bin/tvguard-agent";
                        if (BridgeClient.saveAddress(activity, value)) {
                            callback.onSaved(value);
                            dialog.dismiss();
                        } else {
                            preview.setText("地址无效，请输入有效的局域网 IPv4");
                        }
                    }
                });
            }
        });
        dialog.show();
        if (focusButton != null) focusButton.requestFocus();
    }
}
