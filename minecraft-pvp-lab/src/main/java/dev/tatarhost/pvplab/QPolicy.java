package dev.tatarhost.pvplab;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/** Shared population Q-learning brain with an elite checkpoint and generation mutations. */
final class QPolicy {
    static final int ACTIONS = 8;
    private static final double ALPHA = 0.14;
    private static final double GAMMA = 0.93;
    private static final double MIN_EPSILON = 0.035;
    private static final Map<String, double[]> VALUES = new HashMap<>();
    private static Map<String, double[]> elite = new HashMap<>();
    private static double epsilon = 0.28;
    private static double bestFitness = Double.NEGATIVE_INFINITY;
    private static long updates;
    private static long generations;

    private QPolicy() {}

    static int choose(String state) {
        double[] row = VALUES.computeIfAbsent(state, ignored -> new double[ACTIONS]);
        if (ThreadLocalRandom.current().nextDouble() < epsilon) {
            return ThreadLocalRandom.current().nextInt(ACTIONS);
        }
        int best = 0;
        for (int i = 1; i < ACTIONS; i++) if (row[i] > row[best]) best = i;
        return best;
    }

    static void update(String state, int action, double reward, String nextState) {
        if (state == null || nextState == null || action < 0 || action >= ACTIONS) return;
        double[] current = VALUES.computeIfAbsent(state, ignored -> new double[ACTIONS]);
        double[] next = VALUES.computeIfAbsent(nextState, ignored -> new double[ACTIONS]);
        double bestNext = next[0];
        for (int i = 1; i < ACTIONS; i++) bestNext = Math.max(bestNext, next[i]);
        current[action] += ALPHA * (reward + GAMMA * bestNext - current[action]);
        updates++;
        epsilon = Math.max(MIN_EPSILON, epsilon * 0.999995);
    }

    static void finish(String state, int action, double reward) {
        if (state == null || action < 0 || action >= ACTIONS) return;
        double[] row = VALUES.computeIfAbsent(state, ignored -> new double[ACTIONS]);
        row[action] += ALPHA * (reward - row[action]);
        updates++;
    }

    /** Keep the strongest population checkpoint; otherwise restore it and perturb exploration. */
    static boolean evolve(double generationBestFitness) {
        generations++;
        if (generationBestFitness > bestFitness) {
            bestFitness = generationBestFitness;
            elite = snapshot();
            epsilon = Math.max(MIN_EPSILON, epsilon * 0.90);
            return true;
        }
        if (!elite.isEmpty()) {
            VALUES.clear();
            elite.forEach((key, value) -> VALUES.put(key, value.clone()));
        }
        mutate();
        epsilon = Math.max(MIN_EPSILON, Math.min(0.22, epsilon * 0.96 + 0.012));
        return false;
    }

    private static void mutate() {
        ThreadLocalRandom random = ThreadLocalRandom.current();
        for (double[] row : VALUES.values()) {
            for (int i = 0; i < row.length; i++) {
                if (random.nextDouble() < 0.025) row[i] += random.nextDouble(-0.25, 0.25);
            }
        }
    }

    static Map<String, double[]> snapshot() {
        Map<String, double[]> copy = new HashMap<>();
        VALUES.forEach((key, value) -> copy.put(key, value.clone()));
        return copy;
    }

    static Map<String, double[]> eliteSnapshot() {
        Map<String, double[]> copy = new HashMap<>();
        elite.forEach((key, value) -> copy.put(key, value.clone()));
        return copy;
    }

    static void restore(Map<String, double[]> values, Map<String, double[]> savedElite,
                        double restoredEpsilon, long restoredUpdates,
                        long restoredGenerations, double restoredBestFitness) {
        VALUES.clear();
        copyRows(values, VALUES);
        elite = new HashMap<>();
        copyRows(savedElite, elite);
        if (elite.isEmpty()) elite = snapshot();
        epsilon = Math.max(MIN_EPSILON, Math.min(1.0, restoredEpsilon));
        updates = Math.max(0L, restoredUpdates);
        generations = Math.max(0L, restoredGenerations);
        bestFitness = restoredBestFitness;
    }

    private static void copyRows(Map<String, double[]> source, Map<String, double[]> destination) {
        if (source == null) return;
        source.forEach((key, value) -> {
            if (key == null || value == null) return;
            double[] row = new double[ACTIONS];
            System.arraycopy(value, 0, row, 0, Math.min(value.length, ACTIONS));
            destination.put(key, row);
        });
    }

    static long updates() { return updates; }
    static long generations() { return generations; }
    static int states() { return VALUES.size(); }
    static double epsilon() { return epsilon; }
    static double bestFitness() { return bestFitness; }
}
