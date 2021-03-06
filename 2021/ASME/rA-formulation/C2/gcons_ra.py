import numpy as np
from physics import Constraints, skew, I3, check_SO3, generate_sympy_constraint

AI = 'a_bar_i'
AJ = 'a_bar_j'
SI = 's_bar_p_i'
SJ = 's_bar_q_j'
C = 'c'
F = 'f'
DF = 'f_dot'
DDF = 'f_ddot'
JS_r = "r"
JS_rdot = "r_dot"
JS_A = "A"
JS_omega = "omega"


def distance_fn(body_i, body_j, si, sj):
    """
    d_ij in Haug and Negrut's notation

    Distance between point s_i on body i and point s_j on body j. Used by DP2, D and CD constraints
    """
    return body_j.r + body_j.A @ sj - body_i.r - body_i.A @ si


class Body:
    def __init__(self, r, dr, A, ω, is_ground):
        self.is_ground = is_ground
        self.id = None  # Assigned later for non-ground bodies

        self.r = r
        self.dr = dr
        self.A = A
        self.ω = ω

        self.m = 0
        self.V = 0
        self.J = np.zeros((3, 3))
        self.F = np.zeros((3, 1))

        self.n_ω = np.zeros((3, 1))

        self.r_prev = self.r
        self.A_prev = self.A
        self.dr_prev = self.dr
        self.ω_prev = self.ω

    @classmethod
    def init_from_dict(cls, dict, is_ground=False):
        is_ground = is_ground or dict['name'] == 'ground'

        if is_ground:
            r = np.zeros((3, 1))
            dr = np.zeros((3, 1))
            A = I3
            ω = np.zeros((3, 1))
        else:
            r = np.array([dict[JS_r]]).T
            dr = np.array([dict[JS_rdot]]).T
            A = np.array(dict[JS_A])
            ω = np.array([dict[JS_omega]]).T

            check_SO3(A)

        return cls(r, dr, A, ω, is_ground)

    def cache_rA_values(self):
        self.r_prev = self.r
        self.A_prev = self.A
        self.dr_prev = self.dr
        self.ω_prev = self.ω

    def get_tau(self):
        return -skew(self.ω) @ self.J @ self.ω

    def get_J_term(self, h):
        # NOTE: h**2 terms dropped for now
        return self.J - h*(skew(self.J @ self.ω) - skew(self.ω)
                           @ self.J + self.n_ω)


class DP1:
    cons_type = Constraints.DP1

    def __init__(self, body_i, body_j, ai, aj, f, df, ddf):
        self.body_i = body_i
        self.body_j = body_j

        if body_i.is_ground and body_j.is_ground:
            raise ValueError('Both bodies cannot be ground')

        self.ai = ai
        self.aj = aj

        self.f = lambda t: 0
        self.df = lambda t: 0
        self.ddf = lambda t: 0

    @classmethod
    def init_from_dict(cls, dict, body_i, body_j):
        ai = np.array([dict[AI]]).T
        aj = np.array([dict[AJ]]).T

        return cls(body_i, body_j, ai, aj, dict[F], dict[DF], dict[DDF])

    def get_phi(self, t):
        Ai = self.body_i.A
        Aj = self.body_j.A

        return self.ai.T @ Ai.T @ Aj @ self.aj - self.f(t)

    def get_gamma(self, t):
        Ai = self.body_i.A
        Aj = self.body_j.A
        ωi = skew(self.body_i.ω)
        ωj = skew(self.body_j.ω)

        term_1 = -self.aj.T @ (Aj.T @ Ai @ ωi @ ωi + ωj @
                               ωj @ Aj.T @ Ai) @ self.ai
        term_2 = 2 * self.body_j.ω.T @ skew(self.aj) @ Aj.T @ Ai @ skew(
            self.ai) @ self.body_i.ω
        return term_1 + term_2 + self.ddf(t)

    def get_nu(self, t):
        return self.df(t)

    def get_phi_r(self, t):
        return []

    def get_pi(self, t):
        Ai = self.body_i.A
        Aj = self.body_j.A

        Π = []
        if not self.body_i.is_ground:
            Π.append((self.body_i.id, -self.aj.T @ Aj.T @ Ai @ skew(self.ai)))
        if not self.body_j.is_ground:
            Π.append((self.body_j.id, -self.ai.T @ Ai.T @ Aj @ skew(self.aj)))
        return Π

    def get_reaction_force_r(self, t):
        nb = 1 if self.body_i.is_ground or self.body_j.is_ground else 2
        return np.zeros((3*nb, 3*nb))

    def get_reaction_force_A(self, t):
        Ai = self.body_i.A
        Aj = self.body_j.A

        a11 = skew(self.ai) @ skew(Ai.T @ Aj @ self.aj)
        a22 = skew(self.aj) @ skew(Aj.T @ Ai @ self.ai)

        if self.body_i.is_ground:
            return a22

        if self.body_j.is_ground:
            return a11

        a12 = -skew(self.ai) @ Ai.T @ Aj @ skew(self.aj)
        a21 = -skew(self.aj) @ Aj.T @ Ai @ skew(self.ai)

        return np.block([[a11, a12], [a21, a22]])

    def set_constraint_fn(self, f_sym, var):
        f, df, ddf = generate_sympy_constraint(f_sym, var)

        self.f = f
        self.df = df
        self.ddf = ddf


class CD:
    cons_type = Constraints.CD

    def __init__(self, body_i, body_j, si, sj, c, f, df, ddf):
        self.body_i = body_i
        self.body_j = body_j

        if body_i.is_ground and body_j.is_ground:
            raise ValueError('Both bodies cannot be ground')

        self.si = si
        self.sj = sj

        self.c = c

        self.f = lambda t: 0
        self.df = lambda t: 0
        self.ddf = lambda t: 0

    @classmethod
    def init_from_dict(cls, dict, body_i, body_j):
        si = np.array([dict[SI]]).T
        sj = np.array([dict[SJ]]).T
        c = np.array([dict[C]]).T

        return cls(body_i, body_j, si, sj, c, dict[F], dict[DF], dict[DDF])

    def d_ij(self):
        """
        Compact function call for distance between two points
        """
        return distance_fn(self.body_i, self.body_j, self.si, self.sj)

    def get_phi(self, t):
        return self.c.T @ self.d_ij() - self.f(t)

    def get_gamma(self, t):
        Ai = self.body_i.A
        Aj = self.body_j.A
        ωi = skew(self.body_i.ω)
        ωj = skew(self.body_j.ω)

        return self.c.T @ (Ai @ ωi @ ωi @ self.si - Aj @ ωj @ ωj @ self.sj) + self.ddf(t)

    def get_nu(self, t):
        return self.df(t)

    def get_phi_r(self, t):
        Φr = []
        if not self.body_i.is_ground:
            Φr.append((self.body_i.id, -self.c.T))
        if not self.body_j.is_ground:
            Φr.append((self.body_j.id, self.c.T))
        return Φr

    def get_pi(self, t):
        Π = []

        if not self.body_i.is_ground:
            Π.append((self.body_i.id, self.c.T @ self.body_i.A @ skew(self.si)))
        if not self.body_j.is_ground:
            Π.append((self.body_j.id, -self.c.T @
                      self.body_j.A @ skew(self.sj)))
        return Π

    def get_reaction_force_r(self, t):
        nb = 1 if self.body_i.is_ground or self.body_j.is_ground else 2
        return np.zeros((3*nb, 3*nb))

    def get_reaction_force_A(self, t):
        Ai = self.body_i.A
        Aj = self.body_j.A

        a11 = -skew(self.si) @ skew(Ai.T @ self.c)
        a22 = skew(self.sj) @ skew(Aj.T @ self.c)

        if self.body_i.is_ground:
            return a22

        if self.body_j.is_ground:
            return a11

        return np.block([[a11, np.zeros((3, 3))], [np.zeros((3, 3)), a22]])


class DP2:
    cons_type = Constraints.DP2

    def __init__(self, body_i, body_j, ai, si, sj, f, df, ddf):
        self.body_i = body_i
        self.body_j = body_j

        if body_i.is_ground and body_j.is_ground:
            raise ValueError('Both bodies cannot be ground')

        self.ai = ai

        self.si = si
        self.sj = sj

        self.f = lambda t: 0
        self.df = lambda t: 0
        self.ddf = lambda t: 0

    @classmethod
    def init_from_dict(cls, dict, body_i, body_j):
        ai = np.array([dict[AI]]).T

        si = np.array([dict[SI]]).T
        sj = np.array([dict[SJ]]).T

        return cls(body_i, body_j, ai, si, sj, dict[F], dict[DF], dict[DDF])

    def d_ij(self):
        """
        Compact function call for distance between two points
        """
        return distance_fn(self.body_i, self.body_j, self.si, self.sj)

    def get_phi(self, t):
        return self.ai.T @ self.body_i.A.T @ self.d_ij() - self.f(t)

    def get_gamma(self, t):
        ωi = skew(self.body_i.ω)
        ωj = skew(self.body_j.ω)

        t1 = 2 * self.body_i.ω.T @ skew(self.ai) @ self.body_i.A.T @ (
            self.body_i.dr - self.body_j.dr)
        t2 = 2*self.sj.T @ ωj @ self.body_j.A.T @ self.body_i.A @ ωi @ self.ai
        t3 = self.si.T @ ωi @ ωi @ self.ai
        t4 = self.sj.T @ ωj @ ωj @ self.body_j.A.T @ self.body_i.A @ self.ai
        t5 = self.d_ij().T @ self.body_i.A @ ωi @ ωi @ self.ai

        return t1 + t2 - t3 - t4 - t5 + self.ddf(t)

    def get_nu(self, t):
        return self.df(t)

    def get_phi_r(self, t):
        Φr = []

        ai = self.ai.T @ self.body_i.A.T
        if not self.body_i.is_ground:
            Φr.append((self.body_i.id, -ai))
        if not self.body_j.is_ground:
            Φr.append((self.body_j.id, ai))

        return Φr

    def get_pi(self, t):
        Π = []

        if not self.body_i.is_ground:
            i_term = self.ai.T @ skew(
                self.si) - self.d_ij().T @ self.body_i.A @ skew(self.ai)
            Π.append((self.body_i.id, i_term))
        if not self.body_j.is_ground:
            j_term = - \
                self.ai.T @ self.body_i.A.T @ self.body_j.A @ skew(self.sj)
            Π.append((self.body_j.id, j_term))

        return Π


class D:
    cons_type = Constraints.D

    def __init__(self, body_i, body_j, si, sj, f, df, ddf):
        self.body_i = body_i
        self.body_j = body_j

        if body_i.is_ground and body_j.is_ground:
            raise ValueError('Both bodies cannot be ground')

        self.si = si
        self.sj = sj

        self.f = lambda t: 0
        self.df = lambda t: 0
        self.ddf = lambda t: 0

    @classmethod
    def init_from_dict(cls, dict, body_i, body_j):
        si = np.array([dict[SI]]).T
        sj = np.array([dict[SJ]]).T

        return cls(body_i, body_j, si, sj, dict[F], dict[DF], dict[DDF])

    def d_ij(self):
        """
        Compact function call for distance between two points
        """
        return distance_fn(self.body_i, self.body_j, self.si, self.sj)

    def get_phi(self, t):
        dij = self.d_ij()

        return dij.T @ dij - self.f(t)

    def get_gamma(self, t):
        Δ_dr = self.body_j.dr - self.body_i.dr
        ωi = skew(self.body_i.ω)
        ωj = skew(self.body_j.ω)

        Ai = self.body_i.A
        Aj = self.body_j.A

        t1 = -2*Δ_dr.T @ Δ_dr
        t2 = 2*self.sj.T @ ωj @ ωj @ self.sj
        t3 = 2*self.si.T @ ωi @ ωi @ self.si
        t4 = 4*self.sj.T @ ωj @ Aj.T @ Ai @ ωi @ self.si
        t5 = 4*Δ_dr.T @ (Aj @ skew(self.sj) @ self.body_j.ω -
                         Ai @ skew(self.si) @ self.body_i.ω)
        t6 = 2*self.d_ij().T @ (Ai @ ωi @ skew(
            self.si) @ self.body_i.ω - Aj @ ωj @ skew(self.sj) @ self.body_j.ω)

        return t1 + t2 + t3 - t4 + t5 - t6 + self.ddf(t)

    def get_nu(self, t):
        return self.df(t)

    def get_phi_r(self, t):
        Φr = []

        if not self.body_i.is_ground:
            Φr.append((self.body_i.id, -2*self.d_ij().T))
        if not self.body_j.is_ground:
            Φr.append((self.body_j.id, 2*self.d_ij().T))

        return Φr

    def get_pi(self, t):
        Π = []

        if not self.body_i.is_ground:
            term_i = 2*self.d_ij().T @ self.body_i.A @ skew(self.si)
            Π.append((self.body_i.id, term_i))
        if not self.body_j.is_ground:
            term_j = -2*self.d_ij().T @ self.body_j.A @ skew(self.sj)
            Π.append((self.body_j.id, term_j))

        return Π

    def set_constraint_fn(self, f_sym, var):
        f, df, ddf = generate_sympy_constraint(f_sym, var)

        self.f = f
        self.df = df
        self.ddf = ddf


class ConGroup:
    def __init__(self, con_list, nb):
        self.cons = con_list
        self.nc = len(self.cons)
        self.nb = nb

        self.init_storage()

    def init_storage(self):
        self.Φ = np.zeros((self.nc, 1))
        self.Φr = np.zeros((self.nc, 3*self.nb))
        self.Π = np.zeros((self.nc, 3*self.nb))
        self.γ = np.zeros((self.nc, 1))
        self.nu = np.zeros((self.nc, 1))

    def add_constraint(self, con):
        self.cons.append(con)
        self.nc = len(self.cons)

        self.init_storage()

    def get_phi(self, t):
        for i, con in enumerate(self.cons):
            self.Φ[i, 0] = con.get_phi(t)
        return self.Φ

    def get_gamma(self, t):
        for i, con in enumerate(self.cons):
            self.γ[i] = con.get_gamma(t)
        return self.γ

    def get_nu(self, t):
        for i, con in enumerate(self.cons):
            self.nu[i] = con.get_nu(t)
        return self.nu

    def get_phi_r(self, t):
        for i, con in enumerate(self.cons):
            for b_id, phiR in con.get_phi_r(t):
                self.Φr[i, 3*b_id:3*(b_id + 1)] = phiR
        return self.Φr

    def get_pi(self, t):
        for i, con in enumerate(self.cons):
            for b_id, Π in con.get_pi(t):
                self.Π[i, 3*b_id:3*(b_id + 1)] = Π
        return self.Π

    def get_phi_q(self, t):
        return np.concatenate((self.get_phi_r(t), self.get_pi(t)), axis=1)
