module.exports = {
  gasLimit: 10772384,
  Counter: function Counter(init = 0) {
    return {
      counter: init,
      increment() {
        this.counter++
        return this.counter
      },
    }
  },
}
