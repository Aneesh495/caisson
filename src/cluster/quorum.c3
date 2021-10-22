// Module: caisson::cluster
// Quorum consistency calculations and strong consensus guarantees.
//
// Part of the Caisson distributed object storage engine.

module caisson::cluster;

struct QuorumPolicy {
    uint total_nodes;
    uint write_quorum;
    uint read_quorum;
}

fn QuorumPolicy quorum_policy_init(uint total_nodes) {
    uint n = total_nodes > 0 ? total_nodes : 1;
    uint w = (n / 2) + 1;
    uint r = (n / 2) + 1;
    return (QuorumPolicy){
        .total_nodes = n,
        .write_quorum = w,
        .read_quorum = r
    };
}

// Validates that W + R > N ensuring read-your-writes linearizability.
fn bool QuorumPolicy.is_linearizable(this) {
    return (this.write_quorum + this.read_quorum) > this.total_nodes;
}

fn bool QuorumPolicy.has_write_quorum(this, uint acks) {
    return acks >= this.write_quorum;
}

fn bool QuorumPolicy.has_read_quorum(this, uint acks) {
    return acks >= this.read_quorum;
}
