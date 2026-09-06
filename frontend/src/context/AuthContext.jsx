import { createContext, useContext, useState, useCallback } from "react";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [token, setToken] = useState(() => sessionStorage.getItem("sb_token"));
  const [user, setUser] = useState(() => {
    const raw = sessionStorage.getItem("sb_user");
    return raw ? JSON.parse(raw) : null;
  });

  const login = useCallback((newToken, newUser) => {
    setToken(newToken);
    setUser(newUser);
    sessionStorage.setItem("sb_token", newToken);
    sessionStorage.setItem("sb_user", JSON.stringify(newUser));
  }, []);

  const logout = useCallback(() => {
    setToken(null);
    setUser(null);
    sessionStorage.removeItem("sb_token");
    sessionStorage.removeItem("sb_user");
  }, []);

  return (
    <AuthContext.Provider value={{ token, user, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
