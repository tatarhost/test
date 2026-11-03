package dev.tatarhost.pvplab;

import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.client.gui.widget.TextFieldWidget;
import net.minecraft.text.Text;

public final class PvPLabScreen extends Screen {
    private TextFieldWidget modelName;

    public PvPLabScreen() { super(Text.literal("PvP Lab")); }

    @Override
    protected void init() {
        int left = width / 2 - 118;
        int top = height / 2 - 118;
        modelName = new TextFieldWidget(textRenderer, left, top, 236, 20, Text.literal("Имя модели"));
        modelName.setMaxLength(32);
        modelName.setText("champion");
        addDrawableChild(modelName);

        addButton(left, top + 28, "Обучать 50 ИИ · 5 минут", "pvplab train");
        addButton(left, top + 54, "Тренировочный партнёр", "pvplab challenge");
        addButton(left, top + 80, "Статус обучения", "pvplab status");
        addButton(left, top + 106, "Остановить арену", "pvplab stop");
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
        if (value.isEmpty()) return "champion";
        return value.substring(0, Math.min(32, value.length()));
    }

    private void send(String command) {
        if (client != null && client.player != null) client.player.networkHandler.sendChatCommand(command);
    }

    @Override
    public void render(DrawContext context, int mouseX, int mouseY, float delta) {
        renderBackground(context, mouseX, mouseY, delta);
        context.drawCenteredTextWithShadow(textRenderer, Text.literal("P V P   L A B"), width / 2, 30, 0xFFFFFF);
        context.drawCenteredTextWithShadow(textRenderer,
                Text.literal("50 agents · parallel Q-learning · elite evolution"), width / 2, 46, 0xA9B5C4);
        super.render(context, mouseX, mouseY, delta);
    }

    @Override
    public boolean shouldPause() { return false; }
}
