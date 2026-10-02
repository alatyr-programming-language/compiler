## e2e / issue #829 — a loop nest deeper than 64 leaves through the right loop.
##
## x86_64 kept the loop-target frames in `[_; 64]` arrays: the 65th push was skipped while every pop
## still popped, so each later `break` jumped to another loop's done-label and the statements after
## an inner loop were skipped. The frames now live in a word table that grows with the nesting.
##
## 70 loops: two outer loops around a nest of 68 `loop { … ; break }`. 11 is the right answer; a
## lost frame answers 10 or 0.
main := fn() -> u64 {
  mut r : u64 = 0
  loop {
    loop {
      loop {
        loop {
          loop {
            loop {
              loop {
                loop {
                  loop {
                    loop {
                      loop {
                        loop {
                          loop {
                            loop {
                              loop {
                                loop {
                                  loop {
                                    loop {
                                      loop {
                                        loop {
                                          loop {
                                            loop {
                                              loop {
                                                loop {
                                                  loop {
                                                    loop {
                                                      loop {
                                                        loop {
                                                          loop {
                                                            loop {
                                                              loop {
                                                                loop {
                                                                  loop {
                                                                    loop {
                                                                      loop {
                                                                        loop {
                                                                          loop {
                                                                            loop {
                                                                              loop {
                                                                                loop {
                                                                                  loop {
                                                                                    loop {
                                                                                      loop {
                                                                                        loop {
                                                                                          loop {
                                                                                            loop {
                                                                                              loop {
                                                                                                loop {
                                                                                                  loop {
                                                                                                    loop {
                                                                                                      loop {
                                                                                                        loop {
                                                                                                          loop {
                                                                                                            loop {
                                                                                                              loop {
                                                                                                                loop {
                                                                                                                  loop {
                                                                                                                    loop {
                                                                                                                      loop {
                                                                                                                        loop {
                                                                                                                          loop {
                                                                                                                            loop {
                                                                                                                              loop {
                                                                                                                                loop {
                                                                                                                                  loop {
                                                                                                                                    loop {
                                                                                                                                      loop {
                                                                                                                                        loop {
                                                                                                                                          loop {
                                                                                                                                            loop {
                                                                                                                                              break
                                                                                                                                            }
                                                                                                                                            break
                                                                                                                                          }
                                                                                                                                          break
                                                                                                                                        }
                                                                                                                                        break
                                                                                                                                      }
                                                                                                                                      break
                                                                                                                                    }
                                                                                                                                    break
                                                                                                                                  }
                                                                                                                                  break
                                                                                                                                }
                                                                                                                                break
                                                                                                                              }
                                                                                                                              break
                                                                                                                            }
                                                                                                                            break
                                                                                                                          }
                                                                                                                          break
                                                                                                                        }
                                                                                                                        break
                                                                                                                      }
                                                                                                                      break
                                                                                                                    }
                                                                                                                    break
                                                                                                                  }
                                                                                                                  break
                                                                                                                }
                                                                                                                break
                                                                                                              }
                                                                                                              break
                                                                                                            }
                                                                                                            break
                                                                                                          }
                                                                                                          break
                                                                                                        }
                                                                                                        break
                                                                                                      }
                                                                                                      break
                                                                                                    }
                                                                                                    break
                                                                                                  }
                                                                                                  break
                                                                                                }
                                                                                                break
                                                                                              }
                                                                                              break
                                                                                            }
                                                                                            break
                                                                                          }
                                                                                          break
                                                                                        }
                                                                                        break
                                                                                      }
                                                                                      break
                                                                                    }
                                                                                    break
                                                                                  }
                                                                                  break
                                                                                }
                                                                                break
                                                                              }
                                                                              break
                                                                            }
                                                                            break
                                                                          }
                                                                          break
                                                                        }
                                                                        break
                                                                      }
                                                                      break
                                                                    }
                                                                    break
                                                                  }
                                                                  break
                                                                }
                                                                break
                                                              }
                                                              break
                                                            }
                                                            break
                                                          }
                                                          break
                                                        }
                                                        break
                                                      }
                                                      break
                                                    }
                                                    break
                                                  }
                                                  break
                                                }
                                                break
                                              }
                                              break
                                            }
                                            break
                                          }
                                          break
                                        }
                                        break
                                      }
                                      break
                                    }
                                    break
                                  }
                                  break
                                }
                                break
                              }
                              break
                            }
                            break
                          }
                          break
                        }
                        break
                      }
                      break
                    }
                    break
                  }
                  break
                }
                break
              }
              break
            }
            break
          }
          break
        }
        break
      }
      r = r + 1
      break
    }
    r = r + 10
    break
  }
  if r != 11 {
    return r + 100
  }
  42
}
