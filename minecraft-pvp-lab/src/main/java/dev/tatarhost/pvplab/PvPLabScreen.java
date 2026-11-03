// Java 17, Fabric 1.20.4 — in-game GUI for self-play, player sparring, and model files.
package dev.tatarhost.pvplab;

import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.client.gui.widget.TextFieldWidget;
import net.minecraft.text.Text;

public final class PvPLabScreen extends Screen {
    private TextFieldWidget modelName;

    public PvPLabScreen() {
        super(Text.literal("PvP Lab"));
    }

    @Override
    protected void init() {
        int left = this.width / 2 - 118;
        int top = this.height / 2 - 118;

        modelName = new TextFieldWidget(this.textRenderer, left, top, 236, 20, Text.literal("Имя модели"));
        modelName.setMaxLength(32);
        modelName.setText("default");
        addDrawableChild(modelName);

        addButton(left, top + 28, "Дуэль: ИИ против ИИ", "pvplab duel");
        addButton(left, top + 54, "Проверить ИИ против меня", "pvplab challenge");
        addButton(left, top + 80, "Обучать 500 раундов", "pvplab train 500");
        addButton(left, top + 106, "Остановить ботов", "pvplab stop");

        addDrawableChild(ButtonWidget.builder(Text.literal("Сохранить модель"), button ->
                send("pvplab save " + safeName())).dimensions(left, top + 142, 114, 20).build());
        addDrawableChild(ButtonWidget.builder(Text.literal("Загрузить модель"), button ->
                send("pvplab load " + safeName())).dimensions(left + 122, top + 142, 114, 20).build());

        addDrawableChild(ButtonWidget.builder(Text.literal("Закрыть"), button -> close())
                .dimensions(left, top + 172, 236, 20).build());
    }

    private void addButton(int x, int y, String label, String command) {
        addDrawableChild(ButtonWidget.builder(Text.literal(label), button -> send(command))
                .dimensions(x, y, 236, 20).build());
    }

    private String safeName() {
        String value = modelName.getText().replaceAll("[^A-Za-z0-9_-]", "");
        if (value.isEmpty()) return "default";
        return value.substring(0, Math.min(32, value.length()));
    }

    private void send(String command) {
        if (client != null && client.player != null) {
            client.player.networkHandler.sendChatCommand(command);
        }
    }

    @Override
    public void render(DrawContext context, int mouseX, int mouseY, float delta) {
        renderBackground(context, mouseX, mouseY, delta);
        context.drawCenteredTextWithShadow(textRenderer, Text.literal("P V P   L A B"), width / 2, 30, 0xFFFFFF);
        context.drawCenteredTextWithShadow(textRenderer,
                Text.literal("Q-learning · self-play · Fabric 1.20.4"), width / 2, 46, 0xA9B5C4);
        super.render(context, mouseX, mouseY, delta);
    }

    @Override
    public boolean shouldPause() {
        return false;
    }
}
