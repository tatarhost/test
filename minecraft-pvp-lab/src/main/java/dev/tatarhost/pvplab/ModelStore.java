package dev.tatarhost.pvplab;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonParseException;
import net.fabricmc.loader.api.FabricLoader;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

/** Stores the current Q table and the best-ever elite policy. */
final class ModelStore {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();
    private static final Path MODEL_DIR = FabricLoader.getInstance()
            .getConfigDir().resolve("pvplab").resolve("models");

    private ModelStore() {}

    static Path save(String name) throws IOException {
        Path file = resolve(name);
        Files.createDirectories(MODEL_DIR);
        Snapshot snapshot = new Snapshot();
        snapshot.format = 2;
        snapshot.epsilon = QPolicy.epsilon();
        snapshot.updates = QPolicy.updates();
        snapshot.generations = QPolicy.generations();
        snapshot.bestFitness = QPolicy.bestFitness();
        snapshot.values = QPolicy.snapshot();
        snapshot.elite = QPolicy.eliteSnapshot();
        try (Writer writer = Files.newBufferedWriter(file)) {
            GSON.toJson(snapshot, writer);
        }
        return file;
    }

    static boolean load(String name) throws IOException {
        Path file = resolve(name);
        if (!Files.isRegularFile(file)) return false;
        try (Reader reader = Files.newBufferedReader(file)) {
            Snapshot snapshot = GSON.fromJson(reader, Snapshot.class);
            if (snapshot == null || (snapshot.format != 1 && snapshot.format != 2)
                    || snapshot.values == null) {
                throw new JsonParseException("Unsupported or incomplete PvP Lab model");
            }
            QPolicy.restore(snapshot.values, snapshot.elite, snapshot.epsilon,
                    snapshot.updates, snapshot.generations, snapshot.bestFitness);
            return true;
        }
    }

    private static Path resolve(String name) {
        if (name == null || !name.matches("[A-Za-z0-9_-]{1,32}")) {
            throw new IllegalArgumentException("Имя: 1–32 символа A-Z, a-z, 0-9, _ или -");
        }
        Path base = MODEL_DIR.toAbsolutePath().normalize();
        Path file = base.resolve(name + ".json").normalize();
        if (!file.startsWith(base)) throw new IllegalArgumentException("Invalid model path");
        return file;
    }

    private static final class Snapshot {
        int format;
        double epsilon;
        long updates;
        long generations;
        double bestFitness;
        Map<String, double[]> values;
        Map<String, double[]> elite;
    }
}
