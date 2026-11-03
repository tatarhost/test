package dev.tatarhost.pvplab;

import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.entity.Entity;
import net.minecraft.entity.EntityType;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.passive.VillagerEntity;
import net.minecraft.item.ItemStack;
import net.minecraft.item.Items;
import net.minecraft.server.command.CommandManager;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.server.world.ServerWorld;
import net.minecraft.text.Text;
import net.minecraft.util.math.Vec3d;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * PvP Lab population trainer. Fifty visible humanoid Minecraft agents train
 * defensive movement, spacing, evasive routing and target tracking in parallel.
 */
public final class PvPLabMod implements ModInitializer {
    public static final String MOD_ID = "pvplab";
    public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);
    private static final int POPULATION = 50;
    private static final int PAIRS = POPULATION / 2;
    private static final int GENERATION_TICKS = 1200; // 60 seconds
    private static final Map<UUID, Agent> AGENTS = new HashMap<>();
    private static long botCounter;
    private static TrainingSession training;

    @Override
    public void onInitialize() {
        CommandRegistrationCallback.EVENT.register((dispatcher, registryAccess, environment) ->
                dispatcher.register(CommandManager.literal("pvplab")
                        .requires(source -> source.getEntity() instanceof ServerPlayerEntity)
                        .then(CommandManager.literal("train").executes(context -> {
                            ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                            startTraining(player, 300);
                            feedback(context.getSource(), "Запущено обучение 50 ИИ: 25 пар, 5 поколений по 60 секунд.");
                            return 1;
                        }).then(CommandManager.argument("seconds", IntegerArgumentType.integer(60, 3600))
                                .executes(context -> {
                                    ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                                    int seconds = IntegerArgumentType.getInteger(context, "seconds");
                                    startTraining(player, seconds);
                                    feedback(context.getSource(), "Запущено обучение 50 ИИ на " + seconds + " секунд.");
                                    return 1;
                                })))
                        .then(CommandManager.literal("challenge").executes(context -> {
                            ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                            startChallenge(player);
                            feedback(context.getSource(), "Тренировочный агент отслеживает твоё движение и тренирует дистанцию.");
                            return 1;
                        }))
                        .then(CommandManager.literal("stop").executes(context -> {
                            stop(context.getSource().getWorld());
                            feedback(context.getSource(), "Обучение остановлено, агенты удалены.");
                            return 1;
                        }))
                        .then(CommandManager.literal("status").executes(context -> {
                            TrainingSession session = training;
                            String state = session == null ? "не запущено"
                                    : "поколение " + session.generation + ", агентов " + AGENTS.size()
                                    + ", осталось " + Math.max(0, (session.durationTicks - session.elapsedTicks) / 20) + " сек.";
                            feedback(context.getSource(), "PvP Lab: " + state + " | Q-состояний " + QPolicy.states()
                                    + " | обновлений " + QPolicy.updates() + " | лучший fitness "
                                    + String.format(java.util.Locale.ROOT, "%.2f", QPolicy.bestFitness()));
                            return 1;
                        }))
                        .then(CommandManager.literal("save")
                                .then(CommandManager.argument("name", StringArgumentType.word()).executes(context -> {
                                    try {
                                        var path = ModelStore.save(StringArgumentType.getString(context, "name"));
                                        feedback(context.getSource(), "Модель сохранена: " + path.getFileName());
                                    } catch (IOException | IllegalArgumentException exception) {
                                        feedback(context.getSource(), "Ошибка сохранения: " + exception.getMessage());
                                    }
                                    return 1;
                                })))
                        .then(CommandManager.literal("load")
                                .then(CommandManager.argument("name", StringArgumentType.word()).executes(context -> {
                                    try {
                                        String name = StringArgumentType.getString(context, "name");
                                        boolean loaded = ModelStore.load(name);
                                        feedback(context.getSource(), loaded ? "Модель загружена: " + name
                                                : "Файл модели не найден: " + name);
                                    } catch (IOException | IllegalArgumentException exception) {
                                        feedback(context.getSource(), "Ошибка загрузки: " + exception.getMessage());
                                    }
                                    return 1;
                                })))
                )
        );
        ServerTickEvents.END_WORLD_TICK.register(PvPLabMod::tickWorld);
        LOGGER.info("PvP Lab population trainer initialized: {} agents", POPULATION);
    }

    private static void startTraining(ServerPlayerEntity owner, int seconds) {
        ServerWorld world = owner.getServerWorld();
        stop(world);
        training = new TrainingSession(world, owner.getUuid(), owner.getPos(), seconds * 20);
        spawnPopulation(training);
    }

    private static void startChallenge(ServerPlayerEntity owner) {
        ServerWorld world = owner.getServerWorld();
        stop(world);
        VillagerEntity bot = createBot(world, owner.getPos().add(3.0, 0, 0), "TRAINING PARTNER");
        AGENTS.put(bot.getUuid(), new Agent(world, bot.getUuid(), owner.getUuid(), 0));
    }

    private static void spawnPopulation(TrainingSession session) {
        for (int pair = 0; pair < PAIRS; pair++) {
            double angle = (Math.PI * 2.0 * pair) / PAIRS;
            Vec3d radial = new Vec3d(Math.cos(angle), 0, Math.sin(angle));
            Vec3d tangent = new Vec3d(-radial.z, 0, radial.x);
            Vec3d midpoint = session.center.add(radial.multiply(9.0));
            Vec3d first = midpoint.add(tangent.multiply(-1.7));
            Vec3d second = midpoint.add(tangent.multiply(1.7));
            VillagerEntity a = createBot(session.world, first, "AI-" + String.format("%02d", pair * 2 + 1));
            VillagerEntity b = createBot(session.world, second, "AI-" + String.format("%02d", pair * 2 + 2));
            AGENTS.put(a.getUuid(), new Agent(session.world, a.getUuid(), b.getUuid(), pair));
            AGENTS.put(b.getUuid(), new Agent(session.world, b.getUuid(), a.getUuid(), pair));
        }
        ServerPlayerEntity owner = session.world.getServer().getPlayerManager().getPlayer(session.owner);
        if (owner != null) owner.sendMessage(Text.literal("PvP Lab: на арене появились 50 ИИ-агентов (25 пар)."), false);
    }

    private static VillagerEntity createBot(ServerWorld world, Vec3d position, String name) {
        VillagerEntity bot = EntityType.VILLAGER.create(world);
        if (bot == null) throw new IllegalStateException("Could not create training agent");
        bot.refreshPositionAndAngles(position.x, position.y, position.z,
                world.random.nextFloat() * 360.0F, 0.0F);
        bot.setCustomName(Text.literal(name));
        bot.setCustomNameVisible(true);
        bot.setCanPickUpLoot(false);
        // Defensive visual loadout only; agents do not attack or use weapons.
        bot.equipStack(EquipmentSlot.HEAD, new ItemStack(Items.IRON_HELMET));
        bot.equipStack(EquipmentSlot.CHEST, new ItemStack(Items.IRON_CHESTPLATE));
        bot.equipStack(EquipmentSlot.LEGS, new ItemStack(Items.IRON_LEGGINGS));
        bot.equipStack(EquipmentSlot.FEET, new ItemStack(Items.IRON_BOOTS));
        world.spawnEntity(bot);
        return bot;
    }

    private static void tickWorld(ServerWorld world) {
        tickAgents(world);
        TrainingSession session = training;
        if (session == null || session.world != world) return;
        session.elapsedTicks++;
        if (session.elapsedTicks >= session.nextGenerationTick) {
            finishGeneration(session);
            if (session.elapsedTicks >= session.durationTicks) {
                ServerPlayerEntity owner = world.getServer().getPlayerManager().getPlayer(session.owner);
                if (owner != null) owner.sendMessage(Text.literal("Обучение завершено. Лучший fitness: "
                        + String.format(java.util.Locale.ROOT, "%.2f", QPolicy.bestFitness())
                        + ". Модель champion.json сохранена."), false);
                stop(world);
            } else {
                session.generation++;
                session.nextGenerationTick += GENERATION_TICKS;
                removeAgents(world);
                spawnPopulation(session);
            }
        }
    }

    private static void finishGeneration(TrainingSession session) {
        double best = Double.NEGATIVE_INFINITY;
        double total = 0.0;
        int count = 0;
        for (Agent agent : AGENTS.values()) {
            if (agent.world != session.world) continue;
            best = Math.max(best, agent.fitness);
            total += agent.fitness;
            count++;
        }
        if (count == 0) return;
        boolean champion = QPolicy.evolve(best);
        try {
            ModelStore.save("latest");
            if (champion) ModelStore.save("champion");
        } catch (IOException exception) {
            LOGGER.error("Could not persist the generation checkpoint", exception);
        }
        ServerPlayerEntity owner = session.world.getServer().getPlayerManager().getPlayer(session.owner);
        if (owner != null) owner.sendMessage(Text.literal("Поколение " + session.generation
                + ": средний fitness " + String.format(java.util.Locale.ROOT, "%.2f", total / count)
                + ", рекорд " + String.format(java.util.Locale.ROOT, "%.2f", best)
                + (champion ? " — НОВЫЙ ЧЕМПИОН сохранён" : " — чемпион сохранён")), false);
    }

    private static void tickAgents(ServerWorld world) {
        List<UUID> remove = new ArrayList<>();
        for (Agent agent : AGENTS.values()) {
            if (agent.world != world) continue;
            Entity selfEntity = world.getEntity(agent.self);
            Entity targetEntity = world.getEntity(agent.target);
            if (!(selfEntity instanceof VillagerEntity self) || !self.isAlive()) {
                QPolicy.finish(agent.lastState, agent.lastAction, -4.0);
                remove.add(agent.self);
                continue;
            }
            if (!(targetEntity instanceof LivingEntity target) || !target.isAlive()) {
                remove.add(agent.self);
                continue;
            }
            agent.tick(self, target);
        }
        for (UUID id : remove) AGENTS.remove(id);
    }

    private static void stop(net.minecraft.world.World world) {
        if (world instanceof ServerWorld serverWorld) {
            if (training != null && training.world == serverWorld) training = null;
            removeAgents(serverWorld);
        }
    }

    private static void removeAgents(ServerWorld world) {
        Iterator<Map.Entry<UUID, Agent>> iterator = AGENTS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<UUID, Agent> entry = iterator.next();
            if (entry.getValue().world != world) continue;
            Entity entity = world.getEntity(entry.getKey());
            if (entity != null) entity.discard();
            iterator.remove();
        }
    }

    private static void feedback(net.minecraft.server.command.ServerCommandSource source, String message) {
        source.sendFeedback(() -> Text.literal(message), false);
    }

    private static final class Agent {
        private final ServerWorld world;
        private final UUID self;
        private final UUID target;
        private final int cohort;
        private String lastState;
        private int lastAction = -1;
        private int actionTicks;
        private float previousHealth;
        private double previousDistance;
        private double fitness;

        private Agent(ServerWorld world, UUID self, UUID target, int cohort) {
            this.world = world;
            this.self = self;
            this.target = target;
            this.cohort = cohort;
        }

        private void tick(VillagerEntity bot, LivingEntity opponent) {
            bot.getLookControl().lookAt(opponent, 45.0F, 45.0F);
            actionTicks++;
            if (lastState == null) {
                previousHealth = bot.getHealth();
                previousDistance = bot.distanceTo(opponent);
                lastState = observe(bot, opponent);
                lastAction = QPolicy.choose(lastState);
                apply(bot, opponent, lastAction);
                actionTicks = 0;
                return;
            }
            if (actionTicks < 10) return;

            double distance = bot.distanceTo(opponent);
            double reward = distance >= 2.5 && distance <= 5.5 ? 0.45
                    : distance < 1.5 ? -0.60 : distance < 2.5 ? 0.08 : -0.22;
            double movement = Math.sqrt(bot.getVelocity().x * bot.getVelocity().x
                    + bot.getVelocity().z * bot.getVelocity().z);
            reward += movement > 0.025 ? 0.08 : -0.06;
            reward += Math.max(-0.2, Math.min(0.2, previousDistance - distance)) * 0.08;
            reward -= Math.max(0.0, previousHealth - bot.getHealth()) * 1.5;
            if (opponent.getY() - bot.getY() > 1.0) reward -= 0.03;
            fitness += reward;

            String nextState = observe(bot, opponent);
            QPolicy.update(lastState, lastAction, reward, nextState);
            previousHealth = bot.getHealth();
            previousDistance = distance;
            lastState = nextState;
            lastAction = QPolicy.choose(nextState);
            actionTicks = 0;
            apply(bot, opponent, lastAction);
        }

        private static String observe(VillagerEntity self, LivingEntity opponent) {
            double distance = self.distanceTo(opponent);
            int range = distance < 1.5 ? 0 : distance < 2.5 ? 1 : distance < 4.0 ? 2
                    : distance < 5.5 ? 3 : distance < 8.0 ? 4 : 5;
            int health = Math.min(4, Math.max(0, (int) (self.getHealth() / 5.0F)));
            int vertical = opponent.getY() - self.getY() > 1.0 ? 1
                    : opponent.getY() - self.getY() < -1.0 ? -1 : 0;
            double speed = Math.sqrt(self.getVelocity().x * self.getVelocity().x
                    + self.getVelocity().z * self.getVelocity().z);
            int motion = speed > 0.12 ? 2 : speed > 0.025 ? 1 : 0;
            return range + ":" + health + ":" + vertical + ":" + motion;
        }

        private static void apply(VillagerEntity bot, LivingEntity opponent, int action) {
            Vec3d toward = opponent.getPos().subtract(bot.getPos());
            Vec3d flat = new Vec3d(toward.x, 0.0, toward.z);
            if (flat.lengthSquared() < 0.0001) flat = new Vec3d(1.0, 0.0, 0.0);
            Vec3d direction = flat.normalize();
            Vec3d side = new Vec3d(-direction.z, 0.0, direction.x);
            Vec3d destination;
            switch (action) {
                case 0 -> destination = opponent.getPos().subtract(direction.multiply(3.8)).add(side.multiply(2.0));
                case 1 -> destination = opponent.getPos().subtract(direction.multiply(3.8)).subtract(side.multiply(2.0));
                case 2 -> destination = bot.getPos().subtract(direction.multiply(3.5)).add(side.multiply(1.2));
                case 3 -> destination = opponent.getPos().subtract(direction.multiply(3.0)).add(side.multiply(3.0));
                case 4 -> destination = opponent.getPos().subtract(direction.multiply(4.8));
                case 5 -> {
                    bot.getJumpControl().setActive();
                    destination = opponent.getPos().subtract(direction.multiply(3.8)).add(side.multiply(2.5));
                }
                case 6 -> destination = opponent.getPos().subtract(direction.multiply(4.2)).subtract(side.multiply(3.0));
                default -> destination = opponent.getPos().subtract(direction.multiply(3.2));
            }
            bot.getNavigation().startMovingTo(destination.x, destination.y, destination.z,
                    action == 5 ? 1.18 : 1.0);
        }
    }

    private static final class TrainingSession {
        private final ServerWorld world;
        private final UUID owner;
        private final Vec3d center;
        private final int durationTicks;
        private int elapsedTicks;
        private int generation = 1;
        private int nextGenerationTick = GENERATION_TICKS;

        private TrainingSession(ServerWorld world, UUID owner, Vec3d center, int durationTicks) {
            this.world = world;
            this.owner = owner;
            this.center = center;
            this.durationTicks = durationTicks;
        }
    }
}
