// Java 17, Fabric 1.20.4 — tabular Q-learning policy shared by sparring agents.
package dev.tatarhost.pvplab;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

final class QPolicy {
    static final int ACTIONS = 6;
    private static final double LEARNING_RATE = 0.12;
    private static final double DISCOUNT = 0.92;
    private static final double MIN_EPSILON = 0.035;
    private static final Map<String, double[]> VALUES = new HashMap<>();
    private static double epsilon = 0.22;
    private static long updates;

    private QPolicy() {}

    static int choose(String state) {
        double[] row = VALUES.computeIfAbsent(state, ignored -> new double[ACTIONS]);
        if (ThreadLocalRandom.current().nextDouble() < epsilon) {
            return ThreadLocalRandom.current().nextInt(ACTIONS);
        }

        int best = 0;
        for (int i = 1; i < ACTIONS; i++) {
            if (row[i] > row[best]) best = i;
        }
        return best;
    }

    static void update(String state, int action, double reward, String nextState) {
        if (state == null || action < 0 || action >= ACTIONS) return;
        double[] current = VALUES.computeIfAbsent(state, ignored -> new double[ACTIONS]);
        double[] next = VALUES.computeIfAbsent(nextState, ignored -> new double[ACTIONS]);
        double bestNext = next[0];
        for (int i = 1; i < ACTIONS; i++) bestNext = Math.max(bestNext, next[i]);

        current[action] += LEARNING_RATE * (reward + DISCOUNT * bestNext - current[action]);
        updates++;
        epsilon = Math.max(MIN_EPSILON, epsilon * 0.999995);
    }

    static void finish(String state, int action, double reward) {
        if (state == null || action < 0 || action >= ACTIONS) return;
        double[] row = VALUES.computeIfAbsent(state, ignored -> new double[ACTIONS]);
        row[action] += LEARNING_RATE * (reward - row[action]);
        updates++;
    }

    static Map<String, double[]> snapshot() {
        Map<String, double[]> copy = new HashMap<>();
        VALUES.forEach((key, value) -> copy.put(key, value.clone()));
        return copy;
    }

    static void restore(Map<String, double[]> values, double restoredEpsilon, long restoredUpdates) {
        VALUES.clear();
        if (values != null) {
            values.forEach((key, value) -> {
                if (key != null && value != null && value.length == ACTIONS) {
                    VALUES.put(key, value.clone());
                }
            });
        }
        epsilon = Math.max(MIN_EPSILON, Math.min(1.0, restoredEpsilon));
        updates = Math.max(0L, restoredUpdates);
    }

    static long updates() {
        return updates;
    }

    static int states() {
        return VALUES.size();
    }

    static double epsilon() {
        return epsilon;
    }
}
