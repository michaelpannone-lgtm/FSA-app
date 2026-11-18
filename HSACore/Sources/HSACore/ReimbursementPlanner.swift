import Foundation

/// Picks the combination of receipts whose eligible amounts add up closest to a target
/// (a 0/1 subset-sum solved exactly in cents with dynamic programming).
public enum ReimbursementPlanner {
    public struct Candidate: Hashable, Sendable {
        public let id: UUID
        public let cents: Int
        public init(id: UUID, cents: Int) { self.id = id; self.cents = cents }
    }

    public struct Plan: Hashable, Sendable {
        public let ids: [UUID]
        public let totalCents: Int
        public let targetCents: Int
        public var differenceCents: Int { totalCents - targetCents }
        public var isExact: Bool { totalCents == targetCents }
    }

    /// Largest search space handled exactly (about $20,000). Above that we fall back to a greedy pick.
    public static let exactLimitCents = 2_000_000
    /// Upper bound on DP work so planning stays well under a second on an iPhone.
    public static let maxOperations = 300_000_000

    /// - Parameters:
    ///   - candidates: receipts in priority order (e.g. oldest first); earlier ones win ties.
    ///   - allowOver: when true, a total slightly above the target counts if it is closer than the best total below it.
    public static func plan(candidates: [Candidate], targetCents: Int, allowOver: Bool = false) -> Plan {
        let items = candidates.filter { $0.cents > 0 }
        guard targetCents > 0, !items.isEmpty else { return Plan(ids: [], totalCents: 0, targetCents: max(targetCents, 0)) }

        let sumAll = items.reduce(0) { $0 + $1.cents }
        if sumAll <= targetCents {
            return Plan(ids: items.map(\.id), totalCents: sumAll, targetCents: targetCents)
        }

        let maxItem = items.map(\.cents).max() ?? 0
        let ceiling = allowOver ? min(sumAll, targetCents + maxItem) : targetCents
        guard ceiling <= exactLimitCents, ceiling * items.count <= maxOperations else { return greedy(items, targetCents: targetCents) }

        // reachedBy[s] = index of the item that first made sum s reachable, -1 if unreachable.
        var reachedBy = [Int32](repeating: -1, count: ceiling + 1)
        reachedBy[0] = Int32.max // sentinel for the empty set
        for (index, item) in items.enumerated() where item.cents <= ceiling {
            var s = ceiling
            while s >= item.cents {
                if reachedBy[s] == -1, reachedBy[s - item.cents] != -1 {
                    reachedBy[s] = Int32(index)
                }
                s -= 1
            }
        }

        var best = 0
        var s = targetCents
        while s > 0 { if reachedBy[s] != -1 { best = s; break }; s -= 1 }
        if allowOver {
            var over = targetCents + 1
            while over <= ceiling {
                if reachedBy[over] != -1 {
                    if over - targetCents < targetCents - best { best = over }
                    break
                }
                over += 1
            }
        }

        var ids: [UUID] = []
        var remaining = best
        while remaining > 0 {
            let index = Int(reachedBy[remaining])
            ids.append(items[index].id)
            remaining -= items[index].cents
        }
        return Plan(ids: ids.reversed(), totalCents: best, targetCents: targetCents)
    }

    static func greedy(_ items: [Candidate], targetCents: Int) -> Plan {
        var total = 0
        var ids: [UUID] = []
        for item in items.sorted(by: { $0.cents > $1.cents }) where total + item.cents <= targetCents {
            total += item.cents
            ids.append(item.id)
        }
        return Plan(ids: ids, totalCents: total, targetCents: targetCents)
    }
}
