// Java 17, Fabric 1.20.4 — server-side RL sparring, commands, and self-play sessions.
package dev.tatarhost.pvplab;

import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.entity.Entity;
import net.minecraft.entity.EntityType;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.mob.ZombieEntity;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.command.CommandManager;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.server.world.ServerWorld;
import net.minecraft.text.Text;
import net.minecraft.util.math.BlockPos;
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

public final class PvPLabMod implements ModInitializer {
    public static final String MOD_ID = "pvplab";
    public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

    private static final Map<UUID, Agent> AGENTS = new HashMap<>();
    private static long botCounter = 1;
    private static TrainingSession training;

    @Override
    public void onInitialize() {
        CommandRegistrationCallback.EVENT.register((dispatcher, registryAccess, environment) ->
                dispatcher.register(CommandManager.literal("pvplab")
                        .requires(source -> source.getEntity() instanceof ServerPlayerEntity)
                        .then(CommandManager.literal("duel").executes(context -> {
                            ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                            startDuel(player);
                            feedback(context.getSource(), "Дуэль запущена: два ИИ учатся друг против друга.");
                            return 1;
                        }))
                        .then(CommandManager.literal("challenge").executes(context -> {
                            ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                            startChallenge(player);
                            feedback(context.getSource(), "Бот создан. Он тренируется против твоего персонажа без экипировки.");
                            return 1;
                        }))
                        .then(CommandManager.literal("train")
                                .then(CommandManager.argument("episodes", IntegerArgumentType.integer(1, 10000))
                                        .executes(context -> {
                                            ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                                            int episodes = IntegerArgumentType.getInteger(context, "episodes");
                                            startTraining(player, episodes);
                                            feedback(context.getSource(), "Self-play запущен: " + episodes + " раундов.");
                                            return 1;
                                        })))
                        .then(CommandManager.literal("stop").executes(context -> {
                            ServerPlayerEntity player = (ServerPlayerEntity) context.getSource().getEntity();
                            stop(player.getServerWorld());
                            feedback(context.getSource(), "Боты остановлены.");
                            return 1;
                        }))
                        .then(CommandManager.literal("save")
                                .then(CommandManager.argument("name", StringArgumentType.word()).executes(context -> {
                                    String name = StringArgumentType.getString(context, "name");
                                    try {
                                        var path = ModelStore.save(name);
                                        feedback(context.getSource(), "Модель сохранена: " + path.getFileName());
                                    } catch (IOException | IllegalArgumentException exception) {
                                        feedback(context.getSource(), "Ошибка сохранения: " + exception.getMessage());
                                    }
                                    return 1;
                                })))
                        .then(CommandManager.literal("load")
                                .then(CommandManager.argument("name", StringArgumentType.word()).executes(context -> {
                                    String name = StringArgumentType.getString(context, "name");
                                    try {
                                        boolean loaded = ModelStore.load(name);
                                        feedback(context.getSource(), loaded
                                                ? "Модель загружена: " + name
                                                : "Файл модели не найден: " + name);
                                    } catch (IOException | IllegalArgumentException exception) {
                                        feedback(context.getSource(), "Ошибка загрузки: " + exception.getMessage());
                                    }
                                    return 1;
                                }))
                        )
        );

        ServerTickEvents.END_WORLD_TICK.register(PvPLabMod::tickWorld);
        LOGGER.info("PvP Lab initialized for Minecraft 1.20.4");
    }

    private static void startDuel(ServerPlayerEntity owner) {
        ServerWorld world = owner.getServerWorld();
        stop(world);
        spawnPair(world, owner.getPos());
    }

    private static void startChallenge(ServerPlayerEntity owner) {
        ServerWorld world = owner.getServerWorld();
        stop(world);
        Vec3d pos = owner.getPos().add(2.5, 0, 0);
        ZombieEntity bot = createBot(world, pos, "PvP Lab AI");
        bot.setTarget(owner);
        AGENTS.put(bot.getUuid(), new Agent(world, bot.getUuid(), owner.getUuid()));
    }

    private static void startTraining(ServerPlayerEntity owner, int episodes) {
        ServerWorld world = owner.getServerWorld();
        stop(world);
        training = new TrainingSession(world, owner.getUuid(), owner.getPos(), episodes);
        spawnTrainingRound(training);
    }

    private static void spawnPair(ServerWorld world, Vec3d center) {
        ZombieEntity a = createBot(world, center.add(-2.8, 0, 0), "AI Alpha");
        ZombieEntity b = createBot(world, center.add(2.8, 0, 0), "AI Beta");
        a.setTarget(b);
        b.setTarget(a);
        AGENTS.put(a.getUuid(), new Agent(world, a.getUuid(), b.getUuid()));
        AGENTS.put(b.getUuid(), new Agent(world, b.getUuid(), a.getUuid()));
    }

    private static void spawnTrainingRound(TrainingSession session) {
        ZombieEntity a = createBot(session.world, session.center.add(-2.8, 0, 0), "Trainer A");
        ZombieEntity b = createBot(session.world, session.center.add(2.8, 0, 0), "Trainer B");
        a.setTarget(b);
        b.setTarget(a);
        session.botA = a.getUuid();
        session.botB = b.getUuid();
        session.roundEnded = false;
        session.respawnTicks = 0;
        AGENTS.put(a.getUuid(), new Agent(session.world, a.getUuid(), b.getUuid()));
        AGENTS.put(b.getUuid(), new Agent(session.world, b.getUuid(), a.getUuid()));
    }

    private static ZombieEntity createBot(ServerWorld world, Vec3d position, String name) {
        ZombieEntity bot = EntityType.ZOMBIE.create(world);
        if (bot == null) throw new IllegalStateException("Could not create sparring bot");
        bot.refreshPositionAndAngles(position.x, position.y, position.z, world.random.nextFloat() * 360.0F, 0.0F);
        bot.setCustomName(Text.literal(name + " #" + botCounter++));
        bot.setCustomNameVisible(true);
        bot.setCanPickUpLoot(false);
        // Bots stay unarmed; the policy learns movement and timing, while vanilla melee AI handles contact.
        world.spawnEntity(bot);
        return bot;
    }

    private static void tickWorld(ServerWorld world) {
        tickAgents(world);
        if (training == null || training.world != world) return;

        boolean aAlive = isAlive(world, training.botA);
        boolean bAlive = isAlive(world, training.botB);

        if (!training.roundEnded && (!aAlive || !bAlive)) {
            training.roundEnded = true;
            training.completed++;
            training.respawnTicks = 35;
            ServerPlayerEntity owner = world.getServer().getPlayerManager().getPlayer(training.owner);
            if (owner != null && (training.completed % 10 == 0 || training.completed >= training.total)) {
                owner.sendMessage(Text.literal("PvP Lab: завершено " + training.completed + " / " + training.total
                        + " раундов · Q-таблица: " + QPolicy.states() + " состояний"), false);
            }
        } else if (training.roundEnded && --training.respawnTicks <= 0) {
            if (training.completed >= training.total) {
                ServerPlayerEntity owner = world.getServer().getPlayerManager().getPlayer(training.owner);
                if (owner != null) owner.sendMessage(Text.literal("Обучение завершено. Обновлений Q-learning: "
                        + QPolicy.updates()), false);
                training = null;
            } else {
                spawnTrainingRound(training);
            }
        }
    }

    private static void tickAgents(ServerWorld world) {
        List<UUID> remove = new ArrayList<>();
        for (Agent agent : AGENTS.values()) {
            if (agent.world != world) continue;

            Entity selfEntity = world.getEntity(agent.self);
            Entity targetEntity = world.getEntity(agent.target);
            if (!(selfEntity instanceof ZombieEntity self) || !self.isAlive()) {
                QPolicy.finish(agent.lastState, agent.lastAction, -12.0);
                remove.add(agent.self);
                continue;
            }
            if (!(targetEntity instanceof LivingEntity target) || !target.isAlive()) {
                QPolicy.finish(agent.lastState, agent.lastAction, 12.0);
                remove.add(agent.self);
                continue;
            }

            agent.tick(self, target);
        }
        for (UUID id : remove) AGENTS.remove(id);
    }

    private static boolean isAlive(ServerWorld world, UUID id) {
        if (id == null) return false;
        Entity entity = world.getEntity(id);
        return entity instanceof LivingEntity living && living.isAlive();
    }

    private static void stop(ServerWorld world) {
        if (training != null && training.world == world) training = null;
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
        private String lastState;
        private int lastAction = -1;
        private int actionTicks;
        private float previousSelfHealth;
        private float previousTargetHealth;

        private Agent(ServerWorld world, UUID self, UUID target) {
            this.world = world;
            this.self = self;
            this.target = target;
        }

        private void tick(ZombieEntity bot, LivingEntity opponent) {
            bot.setTarget(opponent);
            bot.getLookControl().lookAt(opponent, 35.0F, 35.0F);
            actionTicks++;

            if (lastState == null) {
                previousSelfHealth = bot.getHealth();
                previousTargetHealth = opponent.getHealth();
                lastState = observe(bot, opponent);
                lastAction = QPolicy.choose(lastState);
                apply(bot, opponent, lastAction);
                actionTicks = 0;
                return;
            }

            if (actionTicks < 8) return;

            double dealt = Math.max(0.0, previousTargetHealth - opponent.getHealth());
            double received = Math.max(0.0, previousSelfHealth - bot.getHealth());
            double distance = bot.distanceTo(opponent);
            double positioning = distance >= 1.4 && distance <= 3.1 ? 0.035 : (distance > 7.0 ? -0.08 : 0.0);
            double reward = dealt * 0.75 - received * 0.82 + positioning;

            String nextState = observe(bot, opponent);
            QPolicy.update(lastState, lastAction, reward, nextState);
            previousSelfHealth = bot.getHealth();
            previousTargetHealth = opponent.getHealth();
            lastState = nextState;
            lastAction = QPolicy.choose(nextState);
            actionTicks = 0;
            apply(bot, opponent, lastAction);
        }

        private static String observe(ZombieEntity self, LivingEntity opponent) {
            int selfHp = Math.min(3, Math.max(0, (int) (self.getHealth() / 5.0F)));
            int targetHp = Math.min(3, Math.max(0, (int) (opponent.getHealth() / 5.0F)));
            double distance = self.distanceTo(opponent);
            int range = distance < 2.0 ? 0 : distance < 3.5 ? 1 : distance < 6.0 ? 2 : distance < 10.0 ? 3 : 4;
            int vertical = opponent.getY() - self.getY() > 1.25 ? 1 : opponent.getY() - self.getY() < -1.25 ? -1 : 0;
            return selfHp + ":" + targetHp + ":" + range + ":" + vertical;
        }

        private static void apply(ZombieEntity bot, LivingEntity opponent, int action) {
            Vec3d toward = opponent.getPos().subtract(bot.getPos());
            Vec3d flat = new Vec3d(toward.x, 0.0, toward.z);
            if (flat.lengthSquared() < 0.0001) flat = new Vec3d(1.0, 0.0, 0.0);
            Vec3d direction = flat.normalize();
            Vec3d side = new Vec3d(-direction.z, 0.0, direction.x);

            switch (action) {
                case 0 -> bot.getNavigation().startMovingTo(opponent, 1.05);
                case 1 -> bot.getNavigation().startMovingTo(
                        opponent.getX() - side.x * 2.2, opponent.getY(), opponent.getZ() - side.z * 2.2, 1.0);
                case 2 -> bot.getNavigation().startMovingTo(
                        opponent.getX() + side.x * 2.2, opponent.getY(), opponent.getZ() + side.z * 2.2, 1.0);
                case 3 -> bot.getNavigation().startMovingTo(
                        bot.getX() - direction.x * 3.0, bot.getY(), bot.getZ() - direction.z * 3.0, 1.0);
                case 4 -> {
                    if (bot.distanceTo(opponent) > 2.4) bot.getNavigation().startMovingTo(opponent, 1.28);
                    else bot.getNavigation().stop();
                }
                case 5 -> {
                    bot.getJumpControl().setActive();
                    bot.getNavigation().startMovingTo(opponent, 1.12);
                }
                default -> bot.getNavigation().startMovingTo(opponent, 1.0);
            }
        }
    }

    private static final class TrainingSession {
        private final ServerWorld world;
        private final UUID owner;
        private final Vec3d center;
        private final int total;
        private int completed;
        private UUID botA;
        private UUID botB;
        private boolean roundEnded;
        private int respawnTicks;

        private TrainingSession(ServerWorld world, UUID owner, Vec3d center, int total) {
            this.world = world;
            this.owner = owner;
            this.center = center;
            this.total = total;
        }
    }
}
